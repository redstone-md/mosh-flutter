use crate::observer::{Consumer, Measurements, Observer};
use ringrtc::{
    common::{CallConfig, CallId, Result, units::DataRate},
    webrtc::{
        injectable_network::{InjectableNetwork, Packet},
        media::{VideoFrame, VideoPixelFormat, VideoSource},
        network::NetworkInterfaceType,
        peer_connection::{PeerConnection, SendRates},
        peer_connection_factory::{
            AudioConfig, AudioJitterBufferConfig, PeerConnectionFactory, RffiPeerConnectionKind,
        },
        peer_connection_observer::PeerConnectionObserver,
        ptr::Borrowed,
        stats_observer::{StatsObserver, create_stats_observer},
    },
};
use std::sync::{
    Arc,
    mpsc::{Receiver, sync_channel},
};
use std::time::Duration;

pub struct Endpoint {
    // These native objects drop before the allocations they borrow.
    pub pc: PeerConnection,
    pub stats: Box<StatsObserver>,
    _observer: Box<Observer>,
    _factory: PeerConnectionFactory,
    pub network: InjectableNetwork,
    pub candidates: Receiver<String>,
    pub source: VideoSource,
    pub measurements: Arc<Measurements>,
    pixels: Vec<u8>,
}

impl Endpoint {
    pub fn new(role: &str, sender: impl Fn(Packet) + Send + Sync + 'static) -> Result<Self> {
        let factory = PeerConnectionFactory::new(&AudioConfig::default(), true, "", None)?;
        let network = factory
            .injectable_network()
            .ok_or_else(|| anyhow::anyhow!("injectable network unavailable"))?;
        network.set_sender(Box::new(sender));
        let ip = if role == "caller" {
            "192.0.2.1"
        } else {
            "192.0.2.2"
        };
        network.add_interface("mosh", NetworkInterfaceType::Wifi, ip.parse()?, 1);
        let (candidate_tx, candidates) = sync_channel(32);
        let measurements = Arc::new(Measurements::default());
        let observer = Box::new(Observer {
            role: role.into(),
            candidates: candidate_tx,
            measurements: measurements.clone(),
        });
        // SAFETY: Endpoint owns this stable allocation until pc has dropped.
        let native =
            PeerConnectionObserver::new(Borrowed::from_ptr(&*observer), false, true, true)?;
        let audio = factory.create_outgoing_audio_track()?;
        let source = factory.create_outgoing_video_source()?;
        source.adapt_output_format(1280, 720, 30);
        let video = factory.create_outgoing_video_track(&source)?;
        let pc = factory.create_peer_connection(
            native,
            RffiPeerConnectionKind::Direct,
            &AudioJitterBufferConfig::default(),
            1000,
            &[],
            audio,
            Some(video),
        )?;
        let stats = create_stats_observer(CallId::new(1), Duration::from_secs(1));
        stats.set_stats_snapshot_consumer(Box::new(Consumer(measurements.clone())));
        Ok(Self {
            pc,
            stats,
            _observer: observer,
            _factory: factory,
            network,
            candidates,
            source,
            measurements,
            pixels: vec![128; 1280 * 720 * 3 / 2],
        })
    }

    pub fn enable(&self) -> Result<()> {
        let config = CallConfig::default();
        self.pc
            .configure_audio_encoders(&config.audio_encoder_config);
        self.pc
            .configure_audio_decoders(&config.audio_decoder_config);
        self.pc.set_send_rates(SendRates {
            min: None,
            start: Some(DataRate::from_mbps(1)),
            max: Some(DataRate::from_mbps(3)),
        })?;
        self.pc.set_incoming_media_enabled(true);
        self.pc.set_outgoing_media_enabled(true);
        self.pc.set_audio_recording_enabled(true);
        self.pc.set_audio_playout_enabled(true);
        Ok(())
    }

    pub fn push(&mut self, tick: u8) {
        self.pixels[..1280 * 720].fill(16 + tick % 200);
        self.source.push_frame(VideoFrame::copy_from_slice(
            1280,
            720,
            VideoPixelFormat::I420,
            &self.pixels,
        ));
    }
}

impl Drop for Endpoint {
    fn drop(&mut self) {
        self.pc.close();
    }
}
