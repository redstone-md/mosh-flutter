use super::*;
use crate::native_call::types::Context;
use std::time::Duration;

fn sent(sender_dropped: u64) -> Pipeline {
    Pipeline {
        sender_dropped,
        ..Default::default()
    }
}

#[test]
fn video_stall_recovery_camera_off_and_route_changes_log_once() {
    let now = Instant::now();
    let mut state = State {
        context: Some(Context {
            session_id: "dm".into(),
            call_id: "call".into(),
            superseded: None,
            active: true,
            caller: true,
            caller_signer: "a".into(),
            callee_signer: Some("b".into()),
            peer: "peer".into(),
        }),
        ..Default::default()
    };
    state.snapshot.remote_camera = true;
    let engine = json!({"connection":"Connected", "decoded":12});
    let mut monitor = Monitor::default();
    let route = PeerTransport::Direct;
    let event = monitor
        .observe(route, &state, &engine, sent(0), now)
        .unwrap();
    assert!(event.contains("remote_video=waiting"));
    assert!(monitor
        .observe(route, &state, &engine, sent(0), now)
        .is_none());
    state.present(1, 1, &[0; 4], 0, now, false);
    let event = monitor
        .observe(route, &state, &engine, sent(0), now)
        .unwrap();
    assert!(event.contains("remote_video=live"));
    let later = now + Duration::from_secs(1);
    let event = monitor
        .observe(route, &state, &engine, sent(7), later)
        .unwrap();
    assert!(event.contains("remote_video=stalled"));
    assert!(event.contains("\"sender_dropped\":7"));
    assert!(monitor
        .observe(route, &state, &engine, sent(8), later)
        .is_none());
    state.present(1, 1, &[0; 4], 0, later, false);
    let event = monitor
        .observe(route, &state, &engine, sent(8), later)
        .unwrap();
    assert!(event.contains("remote_video=live"));
    state.snapshot.remote_camera = false;
    let event = monitor
        .observe(route, &state, &engine, sent(8), later)
        .unwrap();
    assert!(event.contains("remote_video=off"));
    let event = monitor
        .observe(PeerTransport::Relayed, &state, &engine, sent(8), later)
        .unwrap();
    assert!(event.contains("route=Relayed"));
}

#[test]
fn audio_logs_when_the_microphone_or_the_peer_falls_silent() {
    let now = Instant::now();
    let state = State::default();
    let route = PeerTransport::Direct;
    let engine = |mic: f64, heard: f64| {
        json!({"connection":"Connected", "microphone": true,
            "audio_sender": {"microphone_energy": mic}, "audio": {"total_energy": heard}})
    };
    let mut monitor = Monitor::default();
    let event = monitor
        .observe(route, &state, &engine(1.0, 0.0), sent(0), now)
        .unwrap();
    assert!(event.contains("microphone=true; capturing=true; hearing=false"));
    assert!(event.contains("input=default; output=default"));
    let event = monitor
        .observe(route, &state, &engine(1.0, 2.0), sent(0), now)
        .unwrap();
    assert!(event.contains("capturing=true; hearing=true"));
    let second = now + Duration::from_secs(1);
    assert!(monitor
        .observe(route, &state, &engine(1.0, 2.0), sent(0), second)
        .is_none());
    let later = now + Duration::from_secs(3);
    let event = monitor
        .observe(route, &state, &engine(1.0, 2.0), sent(0), later)
        .unwrap();
    assert!(event.contains("capturing=false; hearing=false"));
}

#[test]
fn a_connected_call_without_sound_is_reported_once_per_side() {
    let start = Instant::now();
    let mut state = State::default();
    state.snapshot.ready = true;
    let route = PeerTransport::Direct;
    let engine = |mic: f64, packets: u64| {
        json!({"connection":"Connected", "microphone": true,
            "audio_sender": {"microphone_energy": mic},
            "audio": {"packets_received": packets, "total_energy": 0.0}})
    };
    let mut monitor = Monitor::default();
    let mut step = |seconds: u64, mic: f64, packets: u64| {
        let now = start + Duration::from_secs(seconds);
        let engine = engine(mic, packets);
        monitor.observe(route, &state, &engine, sent(0), now);
        monitor.silences(&engine, now)
    };
    assert!(step(0, 0.0, 0).is_empty());
    assert!(step(9, 0.0, 0).is_empty(), "under ten seconds");
    assert_eq!(
        step(10, 0.0, 0),
        [
            "call audio: the microphone captured no sound for 10 s",
            "call audio: no audio packets arrived from the peer for 10 s",
        ]
    );
    assert!(step(30, 0.0, 0).is_empty(), "each side is told once");

    let mut fine = Monitor::default();
    for (seconds, level) in [(0, 1.0), (5, 2.0), (10, 3.0), (11, 4.0)] {
        let now = start + Duration::from_secs(seconds);
        let engine = engine(level, seconds * 50);
        fine.observe(route, &state, &engine, sent(0), now);
        assert!(fine.silences(&engine, now).is_empty(), "{seconds} s");
    }
}

#[test]
fn losses_are_logged_with_the_longest_stalls_while_status_holds() {
    let now = Instant::now();
    let state = State::default();
    let route = PeerTransport::Direct;
    let engine = |full: u64, stale: u64| json!({"connection":"Connected", "queue_dropped": {"full": full, "stale": stale}});
    let ms = |ms: u64| Longest(Duration::from_millis(ms));
    let stalled = |step_ms: u64, drain_ms: u64| Pipeline {
        stalls: Stalls {
            step: ms(step_ms),
            tick: ms(step_ms / 2),
            lock_wait: ms(step_ms / 10),
            drain: ms(drain_ms),
            ..Default::default()
        },
        ..Default::default()
    };
    let mut monitor = Monitor::default();
    let event = monitor
        .observe(route, &state, &engine(0, 0), stalled(20, 3), now)
        .unwrap();
    assert!(event.contains("\"stalls_max_ms\":{\"capture\":0,\"choices\":0,\"drain\":3,\"lock_wait\":2,\"present\":0,\"statistics\":0,\"step\":20,\"tick\":10}"));
    let soon = now + Duration::from_secs(9);
    assert!(monitor
        .observe(route, &state, &engine(0, 5), stalled(310, 4), soon)
        .is_none());
    let later = now + Duration::from_secs(10);
    let event = monitor
        .observe(route, &state, &engine(2, 5), stalled(40, 2), later)
        .unwrap();
    assert!(event.contains("\"engine_dropped\":{\"full\":2,\"stale\":5}"));
    assert!(event.contains("\"stalls_max_ms\":{\"capture\":0,\"choices\":0,\"drain\":4,\"lock_wait\":31,\"present\":0,\"statistics\":0,\"step\":310,\"tick\":155}"));
    let sender_losing = Pipeline {
        sender_dropped: 3,
        ..stalled(40, 2)
    };
    let event = monitor
        .observe(
            route,
            &state,
            &engine(2, 5),
            sender_losing,
            later + Duration::from_secs(10),
        )
        .unwrap();
    assert!(event.contains("\"sender_dropped\":3"));
    let quiet = later + Duration::from_secs(30);
    assert!(
        monitor
            .observe(route, &state, &engine(2, 5), sender_losing, quiet)
            .is_none(),
        "no new losses, no line"
    );
}
