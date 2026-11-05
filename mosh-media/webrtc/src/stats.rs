//! The snapshot fields mosh-core reads, from libwebrtc's standard stats.
use std::sync::{Arc, Mutex};

use libwebrtc::peer_connection::{IceConnectionState, OnIceConnectionChange};
use libwebrtc::stats::RtcStats;
use serde_json::{Value, json};

#[derive(Default)]
pub struct Measurements {
    connection: Arc<Mutex<String>>,
    latest: Mutex<Value>,
}

impl Measurements {
    pub fn connection_observer(&self) -> OnIceConnectionChange {
        let connection = self.connection.clone();
        Box::new(move |state: IceConnectionState| {
            *connection.lock().unwrap() = format!("{state:?}");
        })
    }

    pub fn update(&self, stats: &[RtcStats]) {
        let mut audio = json!({});
        let mut audio_sender = json!({});
        let mut transport = json!({});
        for entry in stats {
            match entry {
                RtcStats::InboundRtp(s) if s.stream.kind == "audio" => {
                    let samples = s.inbound.total_samples_received.max(1) as f64;
                    audio = json!({
                        "packets_received": s.received.packets_received,
                        "packets_lost": s.received.packets_lost,
                        "jitter_ms": s.received.jitter * 1000.0,
                        "concealed_percent": s.inbound.concealed_samples as f64 * 100.0 / samples,
                        "jitter_buffer_ms": if s.inbound.jitter_buffer_emitted_count > 0 {
                            s.inbound.jitter_buffer_delay * 1000.0
                                / s.inbound.jitter_buffer_emitted_count as f64
                        } else { 0.0 },
                        "bytes_received": s.inbound.bytes_received,
                        "energy": s.inbound.audio_level,
                        "total_energy": s.inbound.total_audio_energy,
                    });
                }
                RtcStats::OutboundRtp(s) if s.stream.kind == "audio" => {
                    audio_sender["packets_sent"] = s.sent.packets_sent.into();
                    audio_sender["bytes_sent"] = s.sent.bytes_sent.into();
                }
                RtcStats::MediaSource(s) if s.source.kind == "audio" => {
                    audio_sender["microphone_energy"] = s.audio.total_audio_energy.into();
                }
                RtcStats::RemoteInboundRtp(s) if s.stream.kind == "audio" => {
                    audio_sender["rtt_ms"] = (s.remote_inbound.round_trip_time * 1000.0).into();
                    audio_sender["remote_fraction_lost"] = s.remote_inbound.fraction_lost.into();
                }
                RtcStats::Transport(s) => {
                    transport = json!({"dtls": format!("{:?}", s.transport.dtls_state),
                        "srtp": s.transport.srtp_cipher, "tls": s.transport.dtls_cipher});
                }
                _ => {}
            }
        }
        *self.latest.lock().unwrap() =
            json!({"audio": audio, "audio_sender": audio_sender, "transport": transport});
    }

    pub fn snapshot(&self) -> Value {
        let latest = self.latest.lock().unwrap().clone();
        let received = latest["audio"]["packets_received"].as_u64().unwrap_or(0) > 0;
        json!({
            "connection": *self.connection.lock().unwrap(),
            "audio_received": received,
            "decoded": 0,
            "audio": latest["audio"],
            "audio_sender": latest["audio_sender"],
            "transport": latest["transport"],
            "video": {},
            "encoder": {},
        })
    }
}
