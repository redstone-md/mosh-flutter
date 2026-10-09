use std::net::SocketAddr;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
    mpsc::SyncSender,
};
use std::time::Instant;

use ringrtc::{
    common::Result,
    core::signaling::IceCandidate,
    webrtc::{
        media::{VideoFrame, VideoFrameMetadata},
        peer_connection_observer::{
            IceConnectionState, NetworkRoute, PeerConnectionObserverTrait, TransportProtocol,
        },
        stats_observer::{StatsSnapshot, StatsSnapshotConsumer},
    },
};
use serde_json::{Value, json};

#[derive(Debug, Default)]
pub struct Measurements {
    pub decoded: AtomicUsize,
    pub decoded_720: AtomicUsize,
    pub audio_received: AtomicBool,
    pub audio: Mutex<Value>,
    pub audio_sender: Mutex<Value>,
    pub video: Mutex<Value>,
    pub encoder: Mutex<Value>,
    pub connection: Mutex<String>,
    pub last_media: Mutex<Option<Instant>>,
    pub frames: crate::frames::Frames,
}

impl Measurements {
    pub fn snapshot(&self) -> Value {
        json!({"decoded": self.decoded.load(Ordering::Relaxed),
            "decoded_720": self.decoded_720.load(Ordering::Relaxed),
            "audio_received": self.audio_received.load(Ordering::Relaxed),
            "audio": *self.audio.lock().unwrap(), "video": *self.video.lock().unwrap(),
            "audio_sender": *self.audio_sender.lock().unwrap(),
            "connection": *self.connection.lock().unwrap(),
            "media_age_ms": self.last_media.lock().unwrap().map(|at| at.elapsed().as_millis() as u64),
            "encoder": *self.encoder.lock().unwrap()})
    }
}

#[derive(Debug)]
pub struct Consumer(pub Arc<Measurements>);

impl StatsSnapshotConsumer for Consumer {
    fn on_stats_snapshot_ready(&self, stats: &StatsSnapshot) {
        let measurements = &self.0;
        match stats {
            StatsSnapshot::AudioSender(s) => {
                *measurements.audio_sender.lock().unwrap() = json!({
                    "packets_per_second": s.packets_per_second, "bitrate": s.bitrate,
                    "energy": s.audio_energy,
                });
            }
            StatsSnapshot::AudioReceiver(s) => {
                if s.packets_per_second > 0.0 {
                    measurements.audio_received.store(true, Ordering::Relaxed);
                    *measurements.last_media.lock().unwrap() = Some(Instant::now());
                }
                *measurements.audio.lock().unwrap() = json!({
                    "packets_per_second": s.packets_per_second, "bitrate": s.bitrate,
                    "energy": s.audio_energy, "loss_percent": s.packets_lost_pct,
                    "concealed_percent": s.concealed_samples_pct,
                })
            }
            StatsSnapshot::VideoReceiver(s) => {
                *measurements.video.lock().unwrap() = json!({
                    "fps": s.framerate, "width": s.width, "height": s.height,
                    "bitrate": s.bitrate, "loss_percent": s.packets_lost_pct,
                    "codec": format!("{:?}", s.codec), "decoder": s.decoder_implementation,
                    "decode_ms": s.decode_time_per_frame,
                })
            }
            StatsSnapshot::VideoSender(s) => {
                *measurements.encoder.lock().unwrap() = json!({
                    "fps": s.framerate, "width": s.width, "height": s.height,
                    "bitrate": s.bitrate, "codec": format!("{:?}", s.codec),
                    "implementation": s.encoder_implementation, "encode_ms": s.encode_time_per_frame,
                    "quality_limitation": s.quality_limitation_reason,
                })
            }
            _ => {}
        }
    }
}

pub struct Observer {
    pub role: String,
    pub candidates: SyncSender<String>,
    pub measurements: Arc<Measurements>,
}

impl PeerConnectionObserverTrait for Observer {
    fn log_id(&self) -> &dyn std::fmt::Display {
        &self.role
    }
    fn handle_ice_candidate_gathered(
        &mut self,
        _: IceCandidate,
        sdp: &str,
        _: Option<TransportProtocol>,
    ) -> Result<()> {
        self.candidates.try_send(sdp.to_owned()).map_err(Into::into)
    }
    fn handle_ice_candidate_removed(&mut self, _: SocketAddr) -> Result<()> {
        Ok(())
    }
    fn handle_ice_connection_state_changed(&mut self, state: IceConnectionState) -> Result<()> {
        *self.measurements.connection.lock().unwrap() = format!("{state:?}");
        Ok(())
    }
    fn handle_ice_network_route_changed(&mut self, _: NetworkRoute) -> Result<()> {
        Ok(())
    }
    fn handle_incoming_video_frame(
        &self,
        _: u32,
        _: VideoFrameMetadata,
        frame: Option<VideoFrame>,
    ) -> Result<()> {
        if let Some(frame) = frame {
            *self.measurements.last_media.lock().unwrap() = Some(Instant::now());
            self.measurements.decoded.fetch_add(1, Ordering::Relaxed);
            if frame.width() == 1280 && frame.height() == 720 {
                self.measurements
                    .decoded_720
                    .fetch_add(1, Ordering::Relaxed);
            }
            self.measurements.frames.store(frame);
        }
        Ok(())
    }
}
