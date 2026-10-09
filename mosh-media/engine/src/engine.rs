use crate::{
    endpoint::Endpoint,
    keys::{MediaBinding, Role},
    negotiation::{Description, Negotiator},
};
use ringrtc::{common::Result, webrtc::injectable_network::Packet};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
        mpsc::{Receiver, sync_channel},
    },
    time::{Duration, Instant},
};

pub const MAX_PACKET: usize = 2007;

#[derive(Deserialize)]
pub struct Config {
    pub binding: MediaBinding,
    pub caller: bool,
}

pub struct Engine {
    pub endpoint: Endpoint,
    negotiation: Negotiator,
    packets: Receiver<(Instant, Vec<u8>)>,
    pending_packet: Option<(Instant, Vec<u8>)>,
    caller: bool,
    started: bool,
    microphone: bool,
    video: bool,
    next_stats: Instant,
    dropped: Arc<AtomicU64>,
    audio: Arc<Mutex<[bool; 128]>>,
}

impl Engine {
    pub fn new(config: Config) -> Result<Self> {
        let role = if config.caller {
            Role::Caller
        } else {
            Role::Callee
        };
        let audio = Arc::new(Mutex::new([false; 128]));
        let negotiation = Negotiator::new(config.binding, role, audio.clone())?;
        let (send, packets) = sync_channel(128);
        let dropped = Arc::new(AtomicU64::new(0));
        let measured = dropped.clone();
        let endpoint = Endpoint::new(
            if config.caller { "caller" } else { "callee" },
            move |packet| {
                let bytes = encode(packet);
                if bytes.len() > MAX_PACKET || send.try_send((Instant::now(), bytes)).is_err() {
                    measured.fetch_add(1, Ordering::Relaxed);
                }
            },
        )?;
        Ok(Self {
            endpoint,
            negotiation,
            packets,
            pending_packet: None,
            caller: config.caller,
            started: false,
            microphone: false,
            video: false,
            next_stats: Instant::now(),
            dropped,
            audio,
        })
    }

    pub fn command(&mut self, value: Value) -> Result<Value> {
        match value["action"].as_str().unwrap_or("") {
            "offer" => Ok(serde_json::to_value(
                self.negotiation.offer(&self.endpoint.pc)?,
            )?),
            "remote" => {
                let remote: Description = serde_json::from_value(value["description"].clone())?;
                Ok(serde_json::to_value(
                    self.negotiation.receive(&self.endpoint.pc, remote)?,
                )?)
            }
            "choices" => {
                self.microphone = value["microphone"]
                    .as_bool()
                    .ok_or_else(|| anyhow::anyhow!("missing microphone choice"))?;
                self.video = value["video"]
                    .as_bool()
                    .ok_or_else(|| anyhow::anyhow!("missing camera choice"))?;
                self.endpoint
                    .set_choices(self.started && self.microphone, self.started && self.video);
                Ok(json!({"ok": true}))
            }
            "start" => {
                anyhow::ensure!(
                    self.negotiation.ready(),
                    "selected key agreement is incomplete"
                );
                self.endpoint.enable(self.microphone, self.video)?;
                self.started = true;
                Ok(json!({"ok": true}))
            }
            "tick" => self.tick(value),
            "snapshot" => {
                let mut snapshot = self.endpoint.measurements.snapshot();
                snapshot["ready"] = self.started.into();
                snapshot["microphone"] = (self.started && self.microphone).into();
                snapshot["video_enabled"] = (self.started && self.video).into();
                snapshot["queue_dropped"] = self.dropped.load(Ordering::Relaxed).into();
                Ok(snapshot)
            }
            "devices" => self.devices(),
            "select" => self.select(value),
            "budget" => self.budget(value),
            _ => anyhow::bail!("unknown media command"),
        }
    }

    fn tick(&mut self, value: Value) -> Result<Value> {
        if let Some(candidates) = value["candidates"].as_array() {
            anyhow::ensure!(
                (candidates.is_empty() || self.negotiation.ready()) && candidates.len() <= 32,
                "invalid candidate state"
            );
            for candidate in candidates {
                let sdp = candidate
                    .as_str()
                    .filter(|sdp| sdp.len() <= 2048)
                    .ok_or_else(|| anyhow::anyhow!("invalid virtual network candidate"))?;
                self.endpoint.pc.add_ice_candidate_from_sdp(sdp)?;
            }
        }
        if self.started && Instant::now() >= self.next_stats {
            self.endpoint.pc.get_stats(&self.endpoint.stats)?;
            self.next_stats = Instant::now() + Duration::from_secs(1);
        }
        let candidates: Vec<_> = self.endpoint.candidates.try_iter().take(32).collect();
        Ok(json!({"candidates": candidates}))
    }

    fn devices(&mut self) -> Result<Value> {
        let mut enumerate = |recording| -> Result<Value> {
            let devices = if recording {
                self.endpoint.factory.get_audio_recording_devices()?
            } else {
                self.endpoint.factory.get_audio_playout_devices()?
            };
            Ok(json!(
                devices
                    .into_iter()
                    .map(|device| json!({"id": device.unique_id,
                "name": device.name}))
                    .collect::<Vec<_>>()
            ))
        };
        Ok(json!({"inputs": enumerate(true).unwrap_or(json!([])),
            "outputs": enumerate(false).unwrap_or(json!([]))}))
    }

    fn select(&mut self, value: Value) -> Result<Value> {
        let input_index = value["input"].as_str().map_or(Some(0), |id| {
            self.endpoint
                .factory
                .get_audio_recording_devices()
                .ok()?
                .iter()
                .rposition(|device| device.unique_id == id)
        });
        let output_index = value["output"].as_str().map_or(Some(0), |id| {
            self.endpoint
                .factory
                .get_audio_playout_devices()
                .ok()?
                .iter()
                .rposition(|device| device.unique_id == id)
        });
        let input_ok = input_index.is_some_and(|index| {
            self.endpoint
                .factory
                .set_audio_recording_device(index)
                .is_ok()
        });
        let output_ok = output_index.is_some_and(|index| {
            self.endpoint
                .factory
                .set_audio_playout_device(index)
                .is_ok()
        });
        if !input_ok {
            self.microphone = false;
            self.endpoint.set_choices(false, self.started && self.video);
        }
        if !output_ok {
            let _ = self.endpoint.factory.set_audio_playout_device(0);
        }
        Ok(json!({"input_ok":input_ok, "output_ok":output_ok}))
    }

    fn budget(&mut self, value: Value) -> Result<Value> {
        use ringrtc::{common::units::DataRate, webrtc::peer_connection::SendRates};
        let max = value["max_bps"]
            .as_u64()
            .filter(|max| (64_000..=3_000_000).contains(max))
            .ok_or_else(|| anyhow::anyhow!("invalid send budget"))?;
        let constrained = max < 600_000;
        self.endpoint.source.adapt_output_format(
            if constrained { 640 } else { 1280 },
            if constrained { 360 } else { 720 },
            if constrained { 15 } else { 30 },
        );
        self.endpoint.pc.set_send_rates(SendRates {
            min: None,
            start: Some(DataRate::from_bps(max.min(1_000_000))),
            max: Some(DataRate::from_bps(max)),
        })?;
        Ok(json!({"ok":true}))
    }

    pub fn priority(&self, packet: &[u8]) -> bool {
        let Some(data) = packet.get(7..) else {
            return true;
        };
        if data.len() < 2 || data[0] >> 6 != 2 || (192..=223).contains(&data[1]) {
            return true;
        }
        self.audio
            .lock()
            .is_ok_and(|audio| audio[usize::from(data[1] & 127)])
    }

    pub fn receive(&self, bytes: &[u8]) -> bool {
        if !self.started {
            return false;
        }
        let Some(packet) = decode(bytes, self.caller) else {
            return false;
        };
        self.endpoint.network.receive_udp(packet);
        true
    }

    pub fn copy_packet(&mut self, buffer: &mut [u8]) -> i32 {
        loop {
            let packet = self
                .pending_packet
                .take()
                .or_else(|| self.packets.try_recv().ok());
            let Some((queued, bytes)) = packet else {
                return 0;
            };
            if queued.elapsed() > Duration::from_millis(50) {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            if buffer.len() < bytes.len() {
                self.pending_packet = Some((queued, bytes));
                return -2;
            }
            buffer[..bytes.len()].copy_from_slice(&bytes);
            return bytes.len() as i32;
        }
    }

    pub fn push_rgba(&self, width: u32, height: u32, pixels: &[u8]) -> Result<()> {
        if self.started && self.video {
            self.endpoint.push_rgba(width, height, pixels)?;
        }
        Ok(())
    }
}

fn encode(packet: Packet) -> Vec<u8> {
    let mut bytes = b"MV1".to_vec();
    bytes.extend(packet.source.port().to_be_bytes());
    bytes.extend(packet.dest.port().to_be_bytes());
    bytes.extend(packet.data);
    bytes
}

fn decode(bytes: &[u8], caller: bool) -> Option<Packet> {
    if bytes.len() < 7 || bytes.len() > MAX_PACKET || &bytes[..3] != b"MV1" {
        return None;
    }
    let (source, dest) = if caller {
        ([192, 0, 2, 2], [192, 0, 2, 1])
    } else {
        ([192, 0, 2, 1], [192, 0, 2, 2])
    };
    Some(Packet {
        source: (
            std::net::Ipv4Addr::from(source),
            u16::from_be_bytes([bytes[3], bytes[4]]),
        )
            .into(),
        dest: (
            std::net::Ipv4Addr::from(dest),
            u16::from_be_bytes([bytes[5], bytes[6]]),
        )
            .into(),
        data: bytes[7..].to_vec(),
    })
}

#[cfg(test)]
#[path = "engine_tests.rs"]
mod tests;
