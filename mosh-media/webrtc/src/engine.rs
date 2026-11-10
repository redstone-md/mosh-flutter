//! One call's peer connection on a virtual network. Media is DTLS-SRTP; the
//! certificate fingerprint travels in the SDP inside the MLS-authenticated
//! description, so only the selected device can complete the handshake.
use std::sync::Arc;
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use libwebrtc::{
    audio_track::RtcAudioTrack,
    media_stream_track::MediaStreamTrack,
    peer_connection::{AnswerOptions, BitrateSettings, OfferOptions, PeerConnection, TrackEvent},
    peer_connection_factory::{
        PeerConnectionFactory, RtcConfiguration, native::PeerConnectionFactoryExt,
    },
    rtp_sender::RtpSender,
    rtp_transceiver::RtpTransceiver,
    session_description::SessionDescription,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{audio, carrier::Carrier, frames::Frames, stats::Measurements, video::Camera};
use negotiation::{gather_candidates, parse_candidate, parse_description, session_version};

mod negotiation;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaBinding {
    pub session_id: String,
    pub call_id: String,
    pub caller: String,
    pub callee: String,
    pub media_session: Vec<u8>,
}

#[derive(Deserialize)]
pub struct Config {
    pub binding: MediaBinding,
    pub caller: bool,
}

/// What mosh-core signs and carries: the binding and this side's SDP.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Description {
    pub binding: MediaBinding,
    pub offer: bool,
    pub parameters: Vec<u8>,
}

pub struct Engine {
    runtime: tokio::runtime::Runtime,
    factory: PeerConnectionFactory,
    pub carrier: Arc<Carrier>,
    pc: PeerConnection,
    microphone: RtcAudioTrack,
    pub camera: Camera,
    pub frames: Frames,
    binding: MediaBinding,
    caller: bool,
    local: Option<Description>,
    remote: Option<Description>,
    /// The caller's ICE restart offer is out and its answer is not yet in.
    restarting: bool,
    started: bool,
    microphone_on: bool,
    camera_on: bool,
    recording: bool,
    candidates: Receiver<String>,
    measurements: Measurements,
    next_stats: Instant,
}

impl Engine {
    pub fn new(config: Config) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()?;
        let carrier = Arc::new(Carrier::new(config.caller));
        let factory = PeerConnectionFactory::with_virtual_network(carrier.network());
        factory.acquire_platform_adm();
        factory.set_adm_recording_enabled(false);
        factory.set_adm_playout_enabled(false);
        // Until an Engine exists, its Drop cannot release the audio module.
        let Connection {
            pc,
            microphone,
            camera,
            frames,
            candidates,
            measurements,
        } = connect(&factory, runtime.handle()).inspect_err(|_| factory.release_platform_adm())?;
        Ok(Self {
            runtime,
            factory,
            carrier,
            pc,
            microphone,
            camera,
            frames,
            binding: config.binding,
            caller: config.caller,
            local: None,
            remote: None,
            restarting: false,
            started: false,
            microphone_on: false,
            camera_on: false,
            recording: false,
            candidates,
            measurements,
            next_stats: Instant::now(),
        })
    }

    pub fn command(&mut self, value: Value) -> Result<Value> {
        match value["action"].as_str().unwrap_or("") {
            "offer" => Ok(serde_json::to_value(self.offer()?)?),
            "restart" => Ok(serde_json::to_value(self.restart()?)?),
            "remote" => {
                let remote: Description = serde_json::from_value(value["description"].clone())?;
                Ok(serde_json::to_value(self.receive_description(remote)?)?)
            }
            "choices" => {
                self.microphone_on = value["microphone"].as_bool().context("microphone")?;
                self.camera_on = value["video"].as_bool().context("camera")?;
                self.apply_choices()?;
                Ok(json!({"ok": true}))
            }
            "start" => {
                anyhow::ensure!(self.remote.is_some(), "negotiation is incomplete");
                self.started = true;
                self.factory.set_adm_playout_enabled(true);
                self.apply_choices()?;
                Ok(json!({"ok": true}))
            }
            "tick" => self.tick(&value),
            "snapshot" => {
                let mut snapshot = self.measurements.snapshot();
                snapshot["ready"] = self.started.into();
                snapshot["microphone"] = self.recording.into();
                snapshot["video_enabled"] = self.camera.enabled().into();
                snapshot["queue_dropped"] = self.carrier.outgoing().dropped();
                Ok(snapshot)
            }
            "devices" => Ok(audio::devices(&self.factory)),
            "select" => Ok(audio::select(&self.factory, &value)),
            "budget" => self.budget(&value),
            "surface" => {
                self.frames.show_at(serde_json::from_value(value)?);
                Ok(Value::Null)
            }
            _ => anyhow::bail!("unknown media command"),
        }
    }

    /// Applies the microphone and camera choices once the call has started.
    /// The track carries the microphone only while the device records, so
    /// the snapshot reports whether it actually does.
    fn apply_choices(&mut self) -> Result<()> {
        let on = self.started && self.microphone_on;
        self.factory.set_adm_recording_enabled(on);
        self.recording = on && audio::start_recording(&self.factory);
        self.microphone.set_enabled(self.recording);
        self.camera.set_enabled(self.started && self.camera_on)
    }

    fn offer(&mut self) -> Result<Description> {
        anyhow::ensure!(self.caller, "only the caller creates the offer");
        if let Some(local) = &self.local {
            return Ok(local.clone());
        }
        self.create_offer(false)
    }

    /// A new offer with fresh ICE credentials, for a path that failed. The
    /// call, its tracks and DTLS stay; only the caller restarts, so the two
    /// sides never restart at once. Until the answer arrives, the pending
    /// offer, the first one included, is the one to resend.
    fn restart(&mut self) -> Result<Description> {
        anyhow::ensure!(self.caller, "only the caller restarts ICE");
        if self.remote.is_some() && !self.restarting {
            self.create_offer(true)?;
            self.restarting = true;
        }
        self.local.clone().context("missing local description")
    }

    fn create_offer(&mut self, ice_restart: bool) -> Result<Description> {
        // The bindings' default sets the legacy offerToReceiveAudio to false,
        // which makes the offer send-only and leaves the callee unheard.
        let options = OfferOptions {
            ice_restart,
            offer_to_receive_audio: None,
            offer_to_receive_video: None,
        };
        let offer = self
            .runtime
            .block_on(self.pc.create_offer(options))
            .map_err(|error| anyhow::anyhow!("offer: {error:?}"))?;
        self.set_local(offer, true)
    }

    fn receive_description(&mut self, remote: Description) -> Result<Description> {
        anyhow::ensure!(
            remote.binding == self.binding,
            "description is for another call"
        );
        anyhow::ensure!(remote.offer != self.caller, "wrong description role");
        if !self.is_news(&remote)? {
            return self.local.clone().context("missing local description");
        }
        let description = parse_description(&remote)?;
        self.runtime
            .block_on(self.pc.set_remote_description(description))
            .map_err(|error| anyhow::anyhow!("remote description: {error:?}"))?;
        self.remote = Some(remote);
        self.restarting = false;
        self.carrier.accept();
        if self.caller {
            return self.local.clone().context("offer was not created");
        }
        let answer = self
            .runtime
            .block_on(self.pc.create_answer(AnswerOptions::default()))
            .map_err(|error| anyhow::anyhow!("answer: {error:?}"))?;
        self.set_local(answer, false)
    }

    /// Whether `remote` moves the negotiation on. Signals arrive twice or
    /// late: the peer's session version, which grows with each description
    /// it makes, tells an old one from the next. The caller takes a new
    /// answer only for its pending restart.
    fn is_news(&self, remote: &Description) -> Result<bool> {
        let Some(accepted) = &self.remote else {
            return Ok(true);
        };
        let newer = session_version(remote)? > session_version(accepted)?;
        Ok(newer && (!self.caller || self.restarting))
    }

    fn set_local(&mut self, description: SessionDescription, offer: bool) -> Result<Description> {
        let sdp = description.to_string();
        self.carrier.outgoing().learn(&sdp);
        self.runtime
            .block_on(self.pc.set_local_description(description))
            .map_err(|error| anyhow::anyhow!("local description: {error:?}"))?;
        let local = Description {
            binding: self.binding.clone(),
            offer,
            parameters: sdp.into_bytes(),
        };
        self.local = Some(local.clone());
        Ok(local)
    }

    fn tick(&mut self, value: &Value) -> Result<Value> {
        if let Some(candidates) = value["candidates"].as_array() {
            anyhow::ensure!(
                (candidates.is_empty() || self.remote.is_some()) && candidates.len() <= 32,
                "invalid candidate state"
            );
            for candidate in candidates {
                self.runtime
                    .block_on(self.pc.add_ice_candidate(parse_candidate(candidate)?))
                    .map_err(|error| anyhow::anyhow!("add candidate: {error:?}"))?;
            }
        }
        if self.started && Instant::now() >= self.next_stats {
            if let Ok(stats) = self.runtime.block_on(self.pc.get_stats()) {
                self.measurements.update(&stats);
            }
            self.next_stats = Instant::now() + Duration::from_secs(1);
        }
        let candidates: Vec<_> = self.candidates.try_iter().take(32).collect();
        Ok(json!({"candidates": candidates}))
    }

    fn budget(&mut self, value: &Value) -> Result<Value> {
        let max = value["max_bps"]
            .as_u64()
            .filter(|max| (64_000..=3_000_000).contains(max))
            .context("invalid send budget")?;
        self.pc
            .set_bitrate(BitrateSettings {
                min_bitrate_bps: None,
                start_bitrate_bps: Some(max.min(1_000_000)),
                max_bitrate_bps: Some(max),
            })
            .map_err(|error| anyhow::anyhow!("budget: {error:?}"))?;
        self.camera.adapt(max)?;
        Ok(json!({"ok": true}))
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.pc.close();
        self.factory.release_platform_adm();
    }
}

struct Connection {
    pc: PeerConnection,
    microphone: RtcAudioTrack,
    camera: Camera,
    frames: Frames,
    candidates: Receiver<String>,
    measurements: Measurements,
}

/// The peer connection with its muted microphone and camera tracks, sending
/// Opus with RED, and the peer's decoded video.
fn connect(
    factory: &PeerConnectionFactory,
    runtime: &tokio::runtime::Handle,
) -> Result<Connection> {
    let pc = factory
        .create_peer_connection(RtcConfiguration::default())
        .map_err(|error| anyhow::anyhow!("peer connection: {error:?}"))?;
    let candidates = gather_candidates(&pc);
    let measurements = Measurements::default();
    pc.on_ice_connection_state_change(Some(measurements.connection_observer()));
    let frames = Frames::default();
    let (watching, spawner) = (frames.clone(), runtime.clone());
    pc.on_track(Some(Box::new(move |event: TrackEvent| {
        if let MediaStreamTrack::Video(track) = event.track {
            watching.watch(&spawner, track);
        }
    })));
    let microphone = factory.create_device_audio_track("microphone");
    microphone.set_enabled(false);
    let sender = pc
        .add_track(MediaStreamTrack::Audio(microphone.clone()), &["mosh"])
        .map_err(|error| anyhow::anyhow!("audio track: {error:?}"))?;
    audio::prefer_red(factory, &transceiver(&pc, &sender)?)?;
    let camera = {
        let _context = runtime.enter();
        Camera::new(factory, &pc)?
    };
    Ok(Connection {
        pc,
        microphone,
        camera,
        frames,
        candidates,
        measurements,
    })
}

/// The transceiver `add_track` created for `sender`.
pub fn transceiver(pc: &PeerConnection, sender: &RtpSender) -> Result<RtpTransceiver> {
    let id = sender.track().map(|track| track.id());
    pc.transceivers()
        .into_iter()
        .find(|transceiver| transceiver.sender().track().map(|track| track.id()) == id)
        .context("track has no transceiver")
}

#[cfg(test)]
#[path = "engine_tests.rs"]
mod tests;
