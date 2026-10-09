//! Real WebRTC factories, SRTP and decoded frames through the binary carrier ABI.
use super::*;
use std::sync::atomic::Ordering;

#[test]
fn caller_can_pump_an_offer_before_the_selected_answer_arrives() {
    let binding = MediaBinding {
        session_id: "dm".into(),
        call_id: "call".into(),
        caller: "a".into(),
        callee: "b".into(),
        media_session: vec![9; 16],
    };
    let mut caller = Engine::new(Config {
        binding,
        caller: true,
    })
    .unwrap();
    caller.command(json!({"action":"offer"})).unwrap();
    assert!(
        caller
            .command(json!({"action":"tick","candidates":[]}))
            .is_ok()
    );
    assert!(
        caller
            .command(json!({"action":"tick","candidates":["candidate"]}))
            .is_err()
    );
}

fn pair() -> (Engine, Engine) {
    let binding = MediaBinding {
        session_id: "dm".into(),
        call_id: "call".into(),
        caller: "caller".into(),
        callee: "callee".into(),
        media_session: vec![9; 16],
    };
    let mut caller = Engine::new(Config {
        binding: binding.clone(),
        caller: true,
    })
    .unwrap();
    let mut callee = Engine::new(Config {
        binding,
        caller: false,
    })
    .unwrap();
    assert!(caller.command(json!({"action":"start"})).is_err());
    let offer = caller.command(json!({"action":"offer"})).unwrap();
    let answer = callee
        .command(json!({"action":"remote", "description":offer}))
        .unwrap();
    caller
        .command(json!({"action":"remote", "description":answer}))
        .unwrap();
    caller
        .command(json!({"action":"choices", "microphone":false,"video":true}))
        .unwrap();
    for engine in [&mut caller, &mut callee] {
        engine.command(json!({"action":"start"})).unwrap();
    }
    (caller, callee)
}

fn transfer(from: &mut Engine, to: &mut Engine) {
    let candidates = from.command(json!({"action":"tick"})).unwrap();
    to.command(json!({"action":"tick","candidates":candidates["candidates"]}))
        .unwrap();
    let mut buffer = [0; MAX_PACKET];
    for _ in 0..128 {
        let length = from.copy_packet(&mut buffer);
        if length == 0 {
            break;
        }
        assert!(length > 0);
        assert!(to.receive(&buffer[..length as usize]));
    }
}

fn pump(caller: &mut Engine, callee: &mut Engine, duration: Duration) {
    let until = Instant::now() + duration;
    let mut tick = 0u8;
    while Instant::now() < until {
        let pixels = vec![tick; 320 * 180 * 4];
        caller.push_rgba(320, 180, &pixels).unwrap();
        transfer(caller, callee);
        transfer(callee, caller);
        tick = tick.wrapping_add(1);
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn receive_only_peer_decodes_and_camera_off_stops_outgoing_video() {
    let (mut caller, mut callee) = pair();
    pump(&mut caller, &mut callee, Duration::from_secs(2));
    let received = callee.endpoint.measurements.decoded.load(Ordering::Relaxed);
    assert!(received > 20, "actual decoded frames: {received}");
    assert_eq!(
        caller.endpoint.measurements.decoded.load(Ordering::Relaxed),
        0
    );
    let mut pixels = vec![0; 320 * 180 * 4];
    let mut metadata = crate::frames::FrameInfo::default();
    assert_eq!(
        callee
            .endpoint
            .measurements
            .frames
            .copy(0, &mut pixels, &mut metadata),
        1
    );
    assert_eq!((metadata.width, metadata.height), (320, 180));
    caller
        .command(json!({"action":"choices","microphone":false,"video":false}))
        .unwrap();
    pump(&mut caller, &mut callee, Duration::from_millis(300));
    let stopped = callee.endpoint.measurements.decoded.load(Ordering::Relaxed);
    pump(&mut caller, &mut callee, Duration::from_millis(400));
    assert_eq!(
        callee.endpoint.measurements.decoded.load(Ordering::Relaxed),
        stopped
    );
    assert!(
        !callee.command(json!({"action":"snapshot"})).unwrap()["video_enabled"]
            .as_bool()
            .unwrap()
    );
}

#[test]
fn rejects_invalid_binary_packets_and_camera_dimensions() {
    let (caller, _) = pair();
    assert!(!caller.receive(b"MV1"));
    assert!(!caller.receive(&[0; MAX_PACKET + 1]));
    assert!(!caller.receive(&[0; 7]));
    assert!(caller.push_rgba(0, 100, &[]).is_err());
    assert!(caller.push_rgba(1920, 1920, &[]).is_err());
    assert!(caller.push_rgba(2, 2, &[0; 15]).is_err());
}

#[test]
#[ignore = "Requires the Linux PulseAudio sine-source and null-sink fixture"]
fn virtual_duplex_audio_survives_video_and_microphone_mute() {
    let (mut caller, mut callee) = pair();
    for engine in [&mut caller, &mut callee] {
        let devices = engine.command(json!({"action":"devices"})).unwrap();
        assert!(
            devices["inputs"]
                .as_array()
                .unwrap()
                .iter()
                .any(|device| device["id"]
                    .as_str()
                    .is_some_and(|id| id.contains("mosh_test_input"))),
            "{devices}"
        );
        engine
            .command(json!({"action":"choices","microphone":true,"video":true}))
            .unwrap();
    }
    pump(&mut caller, &mut callee, Duration::from_secs(4));
    for engine in [&mut caller, &mut callee] {
        let status = engine.command(json!({"action":"snapshot"})).unwrap();
        assert!(
            status["audio"]["energy"].as_f64().unwrap_or(0.0) > 0.0,
            "{status}"
        );
    }
    let video = callee.endpoint.measurements.decoded.load(Ordering::Relaxed);
    caller
        .command(json!({"action":"choices","microphone":false,"video":true}))
        .unwrap();
    pump(&mut caller, &mut callee, Duration::from_secs(3));
    let receiving = callee.command(json!({"action":"snapshot"})).unwrap();
    assert_eq!(
        receiving["audio"]["packets_per_second"].as_f64(),
        Some(0.0),
        "{receiving}"
    );
    assert_eq!(
        caller.command(json!({"action":"snapshot"})).unwrap()["microphone"],
        false
    );
    assert!(callee.endpoint.measurements.decoded.load(Ordering::Relaxed) > video + 20);
    let caller_receiving = caller.command(json!({"action":"snapshot"})).unwrap();
    assert!(
        caller_receiving["audio"]["energy"].as_f64().unwrap_or(0.0) > 0.0,
        "{caller_receiving}"
    );
}
