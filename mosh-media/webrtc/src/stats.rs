//! The snapshot fields mosh-core reads, from libwebrtc's standard stats.
use std::sync::{Arc, Mutex};

use libwebrtc::peer_connection::{IceConnectionState, OnIceConnectionChange};
use libwebrtc::stats::{InboundRtpStats, OutboundRtpStats, RtcStats};
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
        let (mut video, mut encoder, mut camera) = (json!({}), json!({}), json!({}));
        let codec = |id: &str| codec(stats, id);
        for entry in stats {
            match entry {
                RtcStats::InboundRtp(s) if s.stream.kind == "video" => {
                    video = video_receiver(s, codec(&s.stream.codec_id));
                }
                RtcStats::OutboundRtp(s) if s.stream.kind == "video" => {
                    encoder = video_sender(s, codec(&s.stream.codec_id));
                }
                RtcStats::InboundRtp(s) if s.stream.kind == "audio" => audio = audio_receiver(s),
                RtcStats::OutboundRtp(s) if s.stream.kind == "audio" => {
                    audio_sender["packets_sent"] = s.sent.packets_sent.into();
                    audio_sender["bytes_sent"] = s.sent.bytes_sent.into();
                }
                RtcStats::MediaSource(s) if s.source.kind == "video" => {
                    camera = json!({"width": s.video.width, "height": s.video.height});
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
        *self.latest.lock().unwrap() = json!({"audio": audio, "audio_sender": audio_sender,
            "transport": transport, "video": video, "encoder": encoder, "camera": camera});
    }

    pub fn snapshot(&self) -> Value {
        let latest = self.latest.lock().unwrap().clone();
        let received = latest["audio"]["packets_received"].as_u64().unwrap_or(0) > 0;
        json!({
            "connection": *self.connection.lock().unwrap(),
            "audio_received": received,
            "decoded": latest["video"]["decoded"].as_u64().unwrap_or(0),
            "audio": latest["audio"],
            "audio_sender": latest["audio_sender"],
            "transport": latest["transport"],
            "video": latest["video"],
            "encoder": latest["encoder"],
            "camera": latest["camera"],
        })
    }
}

fn codec(stats: &[RtcStats], id: &str) -> Option<String> {
    stats.iter().find_map(|entry| match entry {
        RtcStats::Codec(c) if c.rtc.id == id => {
            // "video/VP9" → "VP9", as the call view shows it.
            let mime = &c.codec.mime_type;
            Some(
                mime.split_once('/')
                    .map_or(mime.as_str(), |(_, name)| name)
                    .to_owned(),
            )
        }
        _ => None,
    })
}

fn audio_receiver(s: &InboundRtpStats) -> Value {
    let samples = s.inbound.total_samples_received.max(1) as f64;
    json!({
        "packets_received": s.received.packets_received,
        "packets_lost": s.received.packets_lost,
        "jitter_ms": s.received.jitter * 1000.0,
        "concealed_percent": s.inbound.concealed_samples as f64 * 100.0 / samples,
        "jitter_buffer_ms": jitter_buffer_ms(s),
        "bytes_received": s.inbound.bytes_received,
        "energy": s.inbound.audio_level,
        "total_energy": s.inbound.total_audio_energy,
    })
}

fn video_receiver(s: &InboundRtpStats, codec: Option<String>) -> Value {
    let decoded = s.inbound.frames_decoded.max(1);
    json!({
        "decoded": s.inbound.frames_decoded,
        "fps": s.inbound.frames_per_second,
        "width": s.inbound.frame_width, "height": s.inbound.frame_height,
        "packets_lost": s.received.packets_lost,
        "codec": codec,
        "decoder": s.inbound.decoder_implementation,
        "decode_ms": s.inbound.total_decode_time * 1000.0 / f64::from(decoded),
        "jitter_buffer_ms": jitter_buffer_ms(s),
    })
}

/// How long the average sample or frame waited in the jitter buffer: the
/// delay that late or bursty packet arrival adds before playout.
fn jitter_buffer_ms(s: &InboundRtpStats) -> f64 {
    if s.inbound.jitter_buffer_emitted_count == 0 {
        return 0.0;
    }
    s.inbound.jitter_buffer_delay * 1000.0 / s.inbound.jitter_buffer_emitted_count as f64
}

/// `hardware` is libwebrtc's powerEfficientEncoder.
fn video_sender(s: &OutboundRtpStats, codec: Option<String>) -> Value {
    let encoded = s.outbound.frames_encoded.max(1);
    json!({
        "fps": s.outbound.frames_per_second,
        "width": s.outbound.frame_width, "height": s.outbound.frame_height,
        "bytes_sent": s.sent.bytes_sent,
        "codec": codec,
        "implementation": s.outbound.encoder_implementation,
        "hardware": s.outbound.power_efficient_encoder,
        "encode_ms": s.outbound.total_encode_time * 1000.0 / f64::from(encoded),
        "quality_limitation": format!("{:?}", s.outbound.quality_limitation_reason),
    })
}
