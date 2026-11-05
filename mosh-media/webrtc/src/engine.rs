//! One call's peer connection on a virtual network. Media is DTLS-SRTP; the
//! certificate fingerprint travels in the SDP inside the MLS-authenticated
//! description, so only the selected device can complete the handshake.
use std::sync::mpsc::{Receiver, sync_channel};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use libwebrtc::{
    audio_track::RtcAudioTrack,
    ice_candidate::IceCandidate,
    media_stream_track::MediaStreamTrack,
    peer_connection::{AnswerOptions, BitrateSettings, OfferOptions, PeerConnection},
    peer_connection_factory::{
        PeerConnectionFactory, RtcConfiguration, native::PeerConnectionFactoryExt,
    },
    session_description::{SdpType, SessionDescription},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{audio, carrier::Carrier, stats::Measurements};

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

#[derive(Serialize, Deserialize)]
struct Candidate {
    mid: String,
    index: i32,
    sdp: String,
}

pub struct Engine {
    runtime: tokio::runtime::Runtime,
    factory: PeerConnectionFactory,
    pub carrier: Carrier,
    pc: PeerConnection,
    microphone: RtcAudioTrack,
    binding: MediaBinding,
    caller: bool,
    local: Option<Description>,
    remote: Option<Description>,
    started: bool,
    microphone_on: bool,
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
        let carrier = Carrier::new(config.caller);
        let factory = PeerConnectionFactory::with_virtual_network(carrier.network());
        factory.acquire_platform_adm();
        factory.set_adm_recording_enabled(false);
        factory.set_adm_playout_enabled(false);
        // Until an Engine exists, its Drop cannot release the audio module.
        let (pc, microphone, candidates, measurements) =
            connect(&factory).inspect_err(|_| factory.release_platform_adm())?;
        Ok(Self {
            runtime,
            factory,
            carrier,
            pc,
            microphone,
            binding: config.binding,
            caller: config.caller,
            local: None,
            remote: None,
            started: false,
            microphone_on: false,
            candidates,
            measurements,
            next_stats: Instant::now(),
        })
    }

    pub fn command(&mut self, value: Value) -> Result<Value> {
        match value["action"].as_str().unwrap_or("") {
            "offer" => Ok(serde_json::to_value(self.offer()?)?),
            "remote" => {
                let remote: Description = serde_json::from_value(value["description"].clone())?;
                Ok(serde_json::to_value(self.receive_description(remote)?)?)
            }
            "choices" => {
                self.microphone_on = value["microphone"].as_bool().context("microphone")?;
                self.apply_choices();
                Ok(json!({"ok": true}))
            }
            "start" => {
                anyhow::ensure!(self.remote.is_some(), "negotiation is incomplete");
                self.started = true;
                self.factory.set_adm_playout_enabled(true);
                self.apply_choices();
                Ok(json!({"ok": true}))
            }
            "tick" => self.tick(&value),
            "snapshot" => {
                let mut snapshot = self.measurements.snapshot();
                snapshot["ready"] = self.started.into();
                snapshot["microphone"] = (self.started && self.microphone_on).into();
                snapshot["video_enabled"] = false.into();
                snapshot["queue_dropped"] = self.carrier.dropped().into();
                Ok(snapshot)
            }
            "devices" => Ok(audio::devices(&self.factory)),
            "select" => Ok(audio::select(&self.factory, &value)),
            "budget" => self.budget(&value),
            _ => anyhow::bail!("unknown media command"),
        }
    }

    fn apply_choices(&self) {
        let on = self.started && self.microphone_on;
        self.microphone.set_enabled(on);
        self.factory.set_adm_recording_enabled(on);
    }

    fn offer(&mut self) -> Result<Description> {
        anyhow::ensure!(self.caller, "only the caller creates the offer");
        if let Some(local) = &self.local {
            return Ok(local.clone());
        }
        let offer = self
            .runtime
            .block_on(self.pc.create_offer(OfferOptions::default()))
            .map_err(|error| anyhow::anyhow!("offer: {error:?}"))?;
        self.set_local(offer, true)
    }

    fn receive_description(&mut self, remote: Description) -> Result<Description> {
        anyhow::ensure!(
            remote.binding == self.binding,
            "description is for another call"
        );
        if let Some(accepted) = &self.remote {
            anyhow::ensure!(accepted == &remote, "media description changed");
            return self.local.clone().context("missing local description");
        }
        anyhow::ensure!(remote.offer != self.caller, "wrong description role");
        anyhow::ensure!(remote.parameters.len() <= 16_384, "description too large");
        let sdp = std::str::from_utf8(&remote.parameters)?;
        anyhow::ensure!(
            sdp.contains("a=fingerprint:"),
            "description lacks a DTLS fingerprint"
        );
        let kind = if remote.offer {
            SdpType::Offer
        } else {
            SdpType::Answer
        };
        let description = SessionDescription::parse(sdp, kind)
            .map_err(|error| anyhow::anyhow!("sdp: {error:?}"))?;
        self.runtime
            .block_on(self.pc.set_remote_description(description))
            .map_err(|error| anyhow::anyhow!("remote description: {error:?}"))?;
        self.remote = Some(remote);
        if self.caller {
            return self.local.clone().context("offer was not created");
        }
        let answer = self
            .runtime
            .block_on(self.pc.create_answer(AnswerOptions::default()))
            .map_err(|error| anyhow::anyhow!("answer: {error:?}"))?;
        self.set_local(answer, false)
    }

    fn set_local(&mut self, description: SessionDescription, offer: bool) -> Result<Description> {
        let sdp = description.to_string();
        self.carrier.learn(&sdp);
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
                let text = candidate.as_str().filter(|text| text.len() <= 2048);
                let candidate: Candidate = serde_json::from_str(text.context("candidate")?)?;
                let parsed = IceCandidate::parse(&candidate.mid, candidate.index, &candidate.sdp)
                    .map_err(|error| anyhow::anyhow!("candidate: {error:?}"))?;
                self.runtime
                    .block_on(self.pc.add_ice_candidate(parsed))
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

    fn budget(&self, value: &Value) -> Result<Value> {
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
        Ok(json!({"ok": true}))
    }

    /// Delivers a packet from Moss once negotiation has a remote side.
    pub fn receive(&self, bytes: &[u8]) -> bool {
        self.remote.is_some() && self.carrier.receive(bytes)
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.pc.close();
        self.factory.release_platform_adm();
    }
}

/// The peer connection with its muted microphone track, sending Opus with RED.
fn connect(
    factory: &PeerConnectionFactory,
) -> Result<(
    PeerConnection,
    RtcAudioTrack,
    Receiver<String>,
    Measurements,
)> {
    let pc = factory
        .create_peer_connection(RtcConfiguration::default())
        .map_err(|error| anyhow::anyhow!("peer connection: {error:?}"))?;
    let candidates = gather_candidates(&pc);
    let measurements = Measurements::default();
    pc.on_ice_connection_state_change(Some(measurements.connection_observer()));
    let microphone = factory.create_device_audio_track("microphone");
    microphone.set_enabled(false);
    pc.add_track(MediaStreamTrack::Audio(microphone.clone()), &["mosh"])
        .map_err(|error| anyhow::anyhow!("audio track: {error:?}"))?;
    audio::prefer_red(factory, &pc)?;
    Ok((pc, microphone, candidates, measurements))
}

/// Queues each gathered ICE candidate as JSON for the next tick.
fn gather_candidates(pc: &PeerConnection) -> Receiver<String> {
    let (sender, candidates) = sync_channel(32);
    pc.on_ice_candidate(Some(Box::new(move |candidate: IceCandidate| {
        let encoded = serde_json::to_string(&Candidate {
            mid: candidate.sdp_mid(),
            index: candidate.sdp_mline_index(),
            sdp: candidate.candidate(),
        });
        if let Ok(encoded) = encoded {
            let _ = sender.try_send(encoded);
        }
    })));
    candidates
}
