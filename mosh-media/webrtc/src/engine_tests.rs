//! Two real engines joined only through the binary carrier, as mosh-core
//! joins them over Moss.
use super::*;
use crate::carrier::MAX_PACKET;
use crate::frames::FrameInfo;

/// A started call with both cameras off.
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
    let offer = caller.command(json!({"action":"offer"})).unwrap();
    let answer = callee
        .command(json!({"action":"remote", "description":offer}))
        .unwrap();
    caller
        .command(json!({"action":"remote", "description":answer}))
        .unwrap();
    for engine in [&mut caller, &mut callee] {
        engine.command(json!({"action":"start"})).unwrap();
    }
    (caller, callee)
}

fn camera(engine: &mut Engine, on: bool) {
    engine
        .command(json!({"action":"choices", "microphone":false, "video":on}))
        .unwrap();
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

/// Sends reddish `width`x`height` camera frames from `from` every 33 ms
/// until `done` holds for `to` or `limit` passes; true if it held.
fn pump(
    from: &mut Engine,
    to: &mut Engine,
    (width, height): (u32, u32),
    limit: Duration,
    done: impl Fn(&Engine) -> bool,
) -> bool {
    let until = Instant::now() + limit;
    let mut pixels = vec![0; width as usize * height as usize * 4];
    let mut tick = 0u8;
    while Instant::now() < until {
        if done(to) {
            return true;
        }
        for (i, pixel) in pixels.chunks_exact_mut(4).enumerate() {
            pixel.copy_from_slice(&[200, 40, (i as u8).wrapping_add(tick), 255]);
        }
        from.camera.push(width, height, &pixels).unwrap();
        transfer(from, to);
        transfer(to, from);
        tick = tick.wrapping_add(7);
        // test-policy: wait https://github.com/redstone-md/mosh-flutter/issues/46 -- a real camera cadence; libwebrtc paces and encodes on its own clock
        std::thread::sleep(Duration::from_millis(33));
    }
    done(to)
}

/// The latest frame's metadata; an empty buffer copies no pixels.
fn info(engine: &Engine) -> FrameInfo {
    let mut info = FrameInfo::default();
    assert!(engine.frames.copy(0, &mut [], &mut info) >= 0);
    info
}

fn sequence(engine: &Engine) -> u64 {
    info(engine).sequence
}

const SMALL: (u32, u32) = (320, 180);
const SECONDS: Duration = Duration::from_secs(8);

#[test]
fn camera_frames_decode_on_the_peer_stop_with_the_camera_and_resume() {
    let (mut caller, mut callee) = pair();
    camera(&mut caller, true);
    assert!(
        pump(&mut caller, &mut callee, SMALL, SECONDS, |to| sequence(to)
            > 20),
        "remote video never decoded"
    );
    let mut pixels = vec![0; 320 * 180 * 4];
    let mut info = FrameInfo::default();
    assert_eq!(callee.frames.copy(0, &mut pixels, &mut info), 1);
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

    camera(&mut caller, false);
    pump(
        &mut caller,
        &mut callee,
        SMALL,
        Duration::from_millis(500),
        |_| false,
    );
    let stopped = sequence(&callee);
    pump(
        &mut caller,
        &mut callee,
        SMALL,
        Duration::from_secs(1),
        |_| false,
    );
    assert_eq!(
        sequence(&callee),
        stopped,
        "video kept flowing after camera off"
    );
    let receiver = callee.command(json!({"action":"snapshot"})).unwrap();
    assert!(receiver["decoded"].as_u64() > Some(20), "{receiver}");

    camera(&mut caller, true);
    assert!(
        pump(&mut caller, &mut callee, SMALL, SECONDS, |to| sequence(to)
            > stopped + 10),
        "video did not resume"
    );
}

#[test]
fn the_callee_sends_video_back() {
    let (mut caller, mut callee) = pair();
    camera(&mut callee, true);
    assert!(
        pump(&mut callee, &mut caller, SMALL, SECONDS, |to| sequence(to)
            > 20),
        "the caller never decoded the callee's video"
    );
}

#[test]
fn a_relayed_route_sends_a_larger_camera_at_most_at_270p15() {
    let (mut caller, mut callee) = pair();
    caller
        .command(json!({"action":"budget", "max_bps":224_000}))
        .unwrap();
    camera(&mut caller, true);
    assert!(pump(
        &mut caller,
        &mut callee,
        SMALL,
        SECONDS,
        |to| sequence(to) > 5
    ));
    // libwebrtc may degrade further on its own; the route's cap applies to
    // every frame from the switch on. The pump runs near 30 fps.
    let switched = sequence(&callee);
    let tallest = std::cell::Cell::new(0);
    let flowing = pump(&mut caller, &mut callee, (640, 360), SECONDS, |to| {
        let info = info(to);
        if info.sequence > switched {
            tallest.set(tallest.get().max(info.width.min(info.height)));
        }
        info.sequence > switched + 30
    });
    assert!(flowing, "video stalled after the camera switch");
    let before = sequence(&callee);
    pump(
        &mut caller,
        &mut callee,
        (640, 360),
        Duration::from_secs(3),
        |_| false,
    );
    let rate = (sequence(&callee) - before) as f64 / 3.0;
    assert!(rate <= 16.5, "a 30 fps camera was sent at {rate} fps");
    assert!(
        tallest.get() <= 270,
        "a 640x360 camera was sent above 270p: {}",
        tallest.get()
    );
}

#[test]
fn a_call_without_camera_sends_no_video() {
    let (mut caller, mut callee) = pair();
    pump(
        &mut caller,
        &mut callee,
        SMALL,
        Duration::from_secs(3),
        |_| false,
    );
    assert_eq!(sequence(&callee), 0);
}
