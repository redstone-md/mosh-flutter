//! Two real engines joined only through the binary carrier, as mosh-core
//! joins them over Moss.
use super::*;
use crate::carrier::MAX_PACKET;
use crate::frames::FrameInfo;

fn pair(camera: bool) -> (Engine, Engine) {
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
    let offer = caller.command(json!({"action":"offer"})).unwrap();
    let answer = callee
        .command(json!({"action":"remote", "description":offer}))
        .unwrap();
    caller
        .command(json!({"action":"remote", "description":answer}))
        .unwrap();
    caller
        .command(json!({"action":"choices", "microphone":false, "video":camera}))
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
    loop {
        let length = from.carrier.copy_packet(&mut buffer);
        if length <= 0 {
            break;
        }
        assert!(to.receive(&buffer[..length as usize]));
    }
}

/// Sends a reddish 320x180 camera frame every 33 ms for `duration`.
fn pump(caller: &mut Engine, callee: &mut Engine, duration: Duration) {
    let until = Instant::now() + duration;
    let mut pixels = vec![0; 320 * 180 * 4];
    let mut tick = 0u8;
    while Instant::now() < until {
        for (i, pixel) in pixels.chunks_exact_mut(4).enumerate() {
            pixel.copy_from_slice(&[200, 40, (i as u8).wrapping_add(tick), 255]);
        }
        caller.camera.push(320, 180, &pixels).unwrap();
        transfer(caller, callee);
        transfer(callee, caller);
        tick = tick.wrapping_add(7);
        // test-policy: wait https://github.com/redstone-md/mosh-flutter/issues/46 -- a real camera cadence; libwebrtc paces and encodes on its own clock
        std::thread::sleep(Duration::from_millis(33));
    }
}

fn latest(engine: &Engine) -> (FrameInfo, Vec<u8>) {
    let mut info = FrameInfo::default();
    let mut pixels = vec![0; 320 * 180 * 4];
    assert!(engine.frames.copy(0, &mut pixels, &mut info) >= 0);
    (info, pixels)
}

#[test]
fn camera_frames_decode_on_the_peer_stop_with_the_camera_and_resume() {
    let (mut caller, mut callee) = pair(true);
    pump(&mut caller, &mut callee, Duration::from_secs(4));
    let (info, pixels) = latest(&callee);
    assert!(info.sequence > 20, "remote video never decoded: {info:?}");
    assert_eq!(
        (info.width, info.height, info.rgba_bytes),
        (320, 180, 320 * 180 * 4)
    );
    assert!(
        pixels[0] > 150 && pixels[1] < 100,
        "colors were lost: {:?}",
        &pixels[..4]
    );
    assert_eq!(pixels[3], 255);
    let sender = caller.command(json!({"action":"snapshot"})).unwrap();
    assert_eq!(sender["video_enabled"], true, "{sender}");

    caller
        .command(json!({"action":"choices", "microphone":false, "video":false}))
        .unwrap();
    pump(&mut caller, &mut callee, Duration::from_millis(500));
    let stopped = latest(&callee).0.sequence;
    pump(&mut caller, &mut callee, Duration::from_secs(1));
    assert_eq!(
        latest(&callee).0.sequence,
        stopped,
        "video kept flowing after camera off"
    );
    let receiver = callee.command(json!({"action":"snapshot"})).unwrap();
    assert!(receiver["decoded"].as_u64() > Some(20), "{receiver}");

    caller
        .command(json!({"action":"choices", "microphone":false, "video":true}))
        .unwrap();
    pump(&mut caller, &mut callee, Duration::from_secs(2));
    assert!(
        latest(&callee).0.sequence > stopped + 10,
        "video did not resume"
    );
}

#[test]
fn a_call_without_camera_sends_no_video() {
    let (mut caller, mut callee) = pair(false);
    pump(&mut caller, &mut callee, Duration::from_secs(3));
    assert_eq!(latest(&callee).0.sequence, 0);
    let sender = caller.command(json!({"action":"snapshot"})).unwrap();
    assert_eq!(
        sender["encoder"]["bytes_sent"].as_u64().unwrap_or(0),
        0,
        "{sender}"
    );
}
