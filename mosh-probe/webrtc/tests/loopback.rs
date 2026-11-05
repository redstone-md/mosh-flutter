//! Two peer connections joined only by the virtual network: ICE, DTLS and
//! Opus audio all cross the closures below, never an OS socket.
use std::net::Ipv4Addr;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use futures::StreamExt;
use libwebrtc::audio_frame::AudioFrame;
use libwebrtc::audio_source::{AudioSourceOptions, native::NativeAudioSource};
use libwebrtc::audio_stream::native::NativeAudioStream;
use libwebrtc::media_stream_track::MediaStreamTrack;
use libwebrtc::peer_connection::{AnswerOptions, OfferOptions, PeerConnection};
use libwebrtc::peer_connection_factory::{
    PeerConnectionFactory, RtcConfiguration, native::PeerConnectionFactoryExt,
};
use libwebrtc::virtual_network::VirtualNetwork;
use tokio::sync::mpsc;

type Link = Arc<OnceLock<VirtualNetwork>>;

fn endpoint(ip: Ipv4Addr, peer: Link) -> (VirtualNetwork, PeerConnectionFactory) {
    let network = VirtualNetwork::new(ip, move |port, to, data| {
        let Some(remote) = peer.get() else {
            return false;
        };
        remote.receive(to.port(), std::net::SocketAddrV4::new(ip, port), data);
        true
    });
    let factory = PeerConnectionFactory::with_virtual_network(&network);
    (network, factory)
}

async fn negotiate(a: &PeerConnection, b: &PeerConnection) {
    let offer = a.create_offer(OfferOptions::default()).await.unwrap();
    assert!(
        offer.to_string().contains("a=fingerprint:"),
        "DTLS fingerprint missing"
    );
    a.set_local_description(offer.clone()).await.unwrap();
    b.set_remote_description(offer).await.unwrap();
    let answer = b.create_answer(AnswerOptions::default()).await.unwrap();
    b.set_local_description(answer.clone()).await.unwrap();
    a.set_remote_description(answer).await.unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn audio_crosses_only_the_virtual_network() {
    let (to_b, to_a): (Link, Link) = (Default::default(), Default::default());
    let (net_a, factory_a) = endpoint(Ipv4Addr::new(192, 0, 2, 1), to_b.clone());
    let (net_b, factory_b) = endpoint(Ipv4Addr::new(192, 0, 2, 2), to_a.clone());
    to_b.set(net_b.clone()).ok();
    to_a.set(net_a.clone()).ok();

    let a = factory_a
        .create_peer_connection(RtcConfiguration::default())
        .unwrap();
    let b = factory_b
        .create_peer_connection(RtcConfiguration::default())
        .unwrap();
    for (from, to) in [(&a, b.clone()), (&b, a.clone())] {
        let runtime = tokio::runtime::Handle::current();
        from.on_ice_candidate(Some(Box::new(move |candidate| {
            assert!(
                candidate.candidate().contains("192.0.2."),
                "{}",
                candidate.candidate()
            );
            let to = to.clone();
            runtime.spawn(async move { to.add_ice_candidate(candidate).await.unwrap() });
        })));
    }
    let (track_tx, mut tracks) = mpsc::unbounded_channel();
    b.on_track(Some(Box::new(move |event| {
        if let MediaStreamTrack::Audio(track) = event.track {
            track_tx.send(track).ok();
        }
    })));

    let source = NativeAudioSource::new(AudioSourceOptions::default(), 48_000, 1, 100);
    let track = factory_a.create_audio_track("mic", source.clone());
    a.add_track(MediaStreamTrack::Audio(track), &["call"])
        .unwrap();
    negotiate(&a, &b).await;

    tokio::spawn(async move {
        let mut frame = AudioFrame::new(48_000, 1, 480);
        for tick in 0u64.. {
            let samples = frame.data.to_mut();
            for (i, sample) in samples.iter_mut().enumerate() {
                let t = (tick * 480 + i as u64) as f64 / 48_000.0;
                *sample = ((t * std::f64::consts::TAU * 440.0).sin() * 8000.0) as i16;
            }
            source.capture_frame(&frame).await.unwrap();
        }
    });

    let remote = tokio::time::timeout(Duration::from_secs(10), tracks.recv())
        .await
        .expect("no remote track")
        .unwrap();
    let mut stream = NativeAudioStream::new(remote, 48_000, 1);
    let heard = tokio::time::timeout(Duration::from_secs(10), async {
        while let Some(frame) = stream.next().await {
            let peak = frame
                .data
                .iter()
                .map(|s| s.unsigned_abs())
                .max()
                .unwrap_or(0);
            if peak > 2000 {
                return peak;
            }
        }
        0
    })
    .await
    .expect("tone never decoded");
    assert!(heard > 2000);
    let transport = a
        .get_stats()
        .await
        .unwrap()
        .into_iter()
        .find_map(|stats| match stats {
            libwebrtc::stats::RtcStats::Transport(transport) => Some(transport.transport),
            _ => None,
        })
        .expect("no transport stats");
    println!(
        "dtls={:?} srtp={} dtls_cipher={}",
        transport.dtls_state, transport.srtp_cipher, transport.dtls_cipher
    );
    assert_eq!(
        transport.dtls_state,
        Some(libwebrtc::stats::DtlsTransportState::Connected)
    );
    assert_eq!(transport.srtp_cipher, "AEAD_AES_256_GCM");
    // TLS_AES_* suites exist only in (D)TLS 1.3 (RFC 8446 B.4).
    assert!(
        transport.dtls_cipher.starts_with("TLS_AES_"),
        "{}",
        transport.dtls_cipher
    );
    a.close();
    b.close();
}
