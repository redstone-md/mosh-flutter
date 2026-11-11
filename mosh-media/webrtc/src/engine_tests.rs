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
        let length = from.carrier.outgoing().copy_packet(&mut buffer);
        if length <= 0 {
            break;
        }
        assert!(to.carrier.receive(&buffer[..length as usize]));
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
    let luma = width as usize * height as usize;
    // BT.601 video range chroma of a red; the luma below keeps it reddish.
    let mut planes = [vec![0; luma], vec![100; luma / 4], vec![211; luma / 4]].concat();
    let mut tick = 0u8;
    while Instant::now() < until {
        if done(to) {
            return true;
        }
        for (i, y) in planes[..luma].iter_mut().enumerate() {
            *y = 80 + (i as u8).wrapping_add(tick) % 32;
        }
        from.camera.push(width, height, &planes).unwrap();
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

#[test]
fn remote_frames_leave_at_the_size_the_window_shows_them() {
    let (mut caller, mut callee) = pair();
    callee
        .command(json!({"action":"surface", "width":160, "height":160}))
        .unwrap();
    camera(&mut caller, true);
    let decoded = |to: &Engine| to.measurements.snapshot()["video"]["width"].as_u64();
    assert!(
        pump(&mut caller, &mut callee, SMALL, SECONDS, |to| sequence(to)
            > 10
            && decoded(to) > Some(0)),
        "remote video never decoded"
    );
    let shown = info(&callee);
    assert_eq!(
        (shown.width, shown.height, shown.rgba_bytes),
        (160, 90, 160 * 90 * 4)
    );
    assert_eq!(
        decoded(&callee),
        Some(320),
        "the decoder kept the full frame"
    );
}

/// The candidates `engine` has gathered so far, waiting for the first.
fn gathered(engine: &mut Engine) -> Value {
    let until = Instant::now() + Duration::from_secs(2);
    loop {
        let candidates = engine.command(json!({"action":"tick"})).unwrap()["candidates"].take();
        if candidates.as_array().is_some_and(|list| !list.is_empty()) || Instant::now() >= until {
            return candidates;
        }
        // test-policy: wait MOSH-88 -- libwebrtc gathers candidates on its own network thread
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn ice_ufrag(description: &Value) -> String {
    let parameters: Vec<u8> = serde_json::from_value(description["parameters"].clone()).unwrap();
    let sdp = String::from_utf8(parameters).unwrap();
    sdp.lines()
        .find_map(|line| line.strip_prefix("a=ice-ufrag:"))
        .unwrap()
        .to_string()
}

#[test]
fn an_ice_restart_keeps_the_call_and_ignores_the_previous_negotiation() {
    let (mut caller, mut callee) = pair();
    let old_candidates = gathered(&mut callee);
    caller
        .command(json!({"action":"tick","candidates":old_candidates}))
        .unwrap();
    camera(&mut caller, true);
    assert!(pump(
        &mut caller,
        &mut callee,
        SMALL,
        SECONDS,
        |to| sequence(to) > 10
    ));
    let old_offer = caller.command(json!({"action":"offer"})).unwrap();
    let old_answer = callee
        .command(json!({"action":"remote", "description":old_offer}))
        .unwrap();

    let offer = caller.command(json!({"action":"restart"})).unwrap();
    assert_ne!(
        ice_ufrag(&offer),
        ice_ufrag(&old_offer),
        "the offer kept its ICE credentials"
    );
    assert_eq!(
        caller.command(json!({"action":"restart"})).unwrap(),
        offer,
        "a pending restart is resent"
    );
    let answer = callee
        .command(json!({"action":"remote", "description":offer}))
        .unwrap();
    assert_ne!(ice_ufrag(&answer), ice_ufrag(&old_answer));
    // Signals arrive late or twice; the old ones change nothing.
    let resent = callee
        .command(json!({"action":"remote", "description":old_offer}))
        .unwrap();
    assert_eq!(resent, answer);
    caller
        .command(json!({"action":"remote", "description":answer}))
        .unwrap();
    caller
        .command(json!({"action":"remote", "description":old_answer}))
        .unwrap();
    caller
        .command(json!({"action":"tick","candidates":old_candidates}))
        .unwrap();

    let before = sequence(&callee);
    assert!(
        pump(&mut caller, &mut callee, SMALL, SECONDS, |to| sequence(to)
            > before + 10),
        "video did not continue after the restart"
    );
    let state = caller.command(json!({"action":"snapshot"})).unwrap();
    assert_eq!(state["connection"], "Connected", "{state}");
}
