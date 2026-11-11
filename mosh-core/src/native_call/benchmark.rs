//! What one video frame costs on the call path, per frame size. It prints
//! rows for `scripts/call-video-bench.mjs` and asserts no speed.
use super::{
    courier::Wire,
    library::{self, Engine},
    texture::{Exported, Texture},
    types::{Context, Frame, Surface},
};
use crate::frb_generated::SseEncode;
use flutter_rust_bridge::for_generated::SseSerializer;
use serde_json::json;
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

const SIZES: [(u32, u32); 3] = [(640, 360), (1280, 720), (1920, 1080)];
const WARM_UPS: usize = 5;
const RUNS: usize = 60;

/// The engine's packets go nowhere: no peer is connected.
struct Silent;
impl Wire for Silent {
    fn send(&mut self, _packet: &[u8], _priority: bool) {}
    fn receive(&mut self, _deliver: &mut dyn FnMut(&[u8])) {}
}

/// Prints the median of `RUNS` timed calls of `run` after `WARM_UPS`
/// untimed ones. `input` and the drop of `run`'s result stay outside the timer.
fn report<I, O>(
    case: &str,
    (width, height): (u32, u32),
    input: impl Fn() -> I,
    run: impl Fn(I) -> O,
) {
    let mut times: Vec<Duration> = (0..WARM_UPS + RUNS)
        .map(|_| {
            let input = input();
            let started = Instant::now();
            let output = run(input);
            let elapsed = started.elapsed();
            drop(output);
            elapsed
        })
        .skip(WARM_UPS)
        .collect();
    times.sort();
    let ms = times[RUNS / 2].as_secs_f64() * 1000.0;
    println!(
        "call-video-bench {}",
        json!({"case": case, "width": width, "height": height, "ms": ms})
    );
}

/// Bytes that vary across the frame, so no conversion sees a flat picture.
fn synthetic(length: usize) -> Vec<u8> {
    (0..length).map(|i| ((i * 31) >> 3) as u8).collect()
}

/// A negotiated caller engine with its camera on, and the callee that
/// answered it. No packet travels between them, so a pushed frame is
/// converted and offered to a sender with no connection.
fn engines() -> [Engine; 2] {
    let context = Context {
        session_id: "dm".into(),
        call_id: "call".into(),
        superseded: None,
        active: true,
        caller: true,
        caller_signer: "caller".into(),
        callee_signer: Some("callee".into()),
        peer: "peer".into(),
    };
    let binding = context.binding(vec![7; 16]).expect("an active call");
    let mut caller = Engine::new(&binding, true, Box::new(Silent)).expect("caller");
    let mut callee = Engine::new(&binding, false, Box::new(Silent)).expect("callee");
    let offer = caller.ask(json!({"action":"offer"})).expect("offer");
    let answer = callee
        .ask(json!({"action":"remote","description":offer}))
        .expect("answer");
    caller
        .ask(json!({"action":"remote","description":answer}))
        .expect("answer applied");
    caller.ask(json!({"action":"start"})).expect("started");
    caller
        .ask(json!({"action":"choices","microphone":false,"video":true}))
        .expect("camera on");
    let snapshot = caller.ask(json!({"action":"snapshot"})).expect("snapshot");
    assert_eq!(snapshot["video_enabled"], true, "the push must convert");
    [caller, callee]
}

/// The engine's conversions of one frame of `size`.
fn conversions(engine: &Engine, size @ (width, height): (u32, u32), pixels: &[u8]) {
    let planar = synthetic(width as usize * height as usize * 3 / 2);
    let half = Surface {
        width: width / 2,
        height: height / 2,
    };
    report(
        "RGBA to I420 and encoder push (`Engine::push`)",
        size,
        || (),
        |()| {
            assert!(engine.push(width, height, pixels));
        },
    );
    // Desktop engines make this libyuv call inside `copy_frame`.
    report(
        "I420 to RGBA (libyuv, as for a decoded frame)",
        size,
        || (),
        |()| library::i420_to_rgba(width, height, &planar).expect("converted"),
    );
    report(
        "preview to half size (`scale_rgba`)",
        size,
        || (),
        |()| {
            library::scale_rgba(width, height, pixels, half)
                .expect("scaled")
                .expect("a smaller frame")
        },
    );
}

/// A frame's way from the call state to the bridge's reply bytes.
fn transfer(size @ (width, height): (u32, u32), pixels: &[u8]) {
    let frame = || Frame {
        session_id: "dm".into(),
        call_id: "call".into(),
        sequence: 1,
        width,
        height,
        local: false,
        source_age_ms: 0,
        pixels: pixels.to_vec(),
    };
    let held = frame();
    report(
        "frame copy for the bridge (`Frame::clone`)",
        size,
        || (),
        |()| held.clone(),
    );
    report(
        "flutter_rust_bridge encode of the frame",
        size,
        frame,
        |frame| {
            let mut serializer = SseSerializer::new();
            Some(frame).sse_encode(&mut serializer);
            serializer
        },
    );
}

/// Stands in for the platform plugin's texture: `present` copies the frame
/// into a buffer it keeps, as `linux/runner/call_video_texture.cc` does.
#[repr(C)]
struct Copying {
    exported: Exported,
    buffer: Mutex<Vec<u8>>,
}

unsafe extern "C" fn copy(exported: *const Exported, pixels: *const u8, width: u32, height: u32) {
    // SAFETY: `exported` is the first field of the `Copying` below.
    let copying = unsafe { &*exported.cast::<Copying>() };
    let bytes = width as usize * height as usize * 4;
    let mut buffer = copying.buffer.lock().unwrap();
    buffer.resize(bytes, 0);
    // SAFETY: the caller hands over `bytes` readable bytes; the buffer holds as many.
    unsafe { std::ptr::copy_nonoverlapping(pixels, buffer.as_mut_ptr(), bytes) };
}

/// A frame's way into a main-window texture, which replaces `transfer` and
/// everything after it. The raster thread's upload is not in the row.
fn texture(size @ (width, height): (u32, u32), pixels: &[u8]) {
    let copying = Copying {
        exported: Exported { present: copy },
        buffer: Mutex::default(),
    };
    // SAFETY: `copying` outlives the texture.
    let texture = unsafe { Texture::at(&raw const copying.exported as i64) }.expect("an address");
    report(
        "texture present (the copy the plugin makes)",
        size,
        || (),
        |()| texture.present(width, height, pixels),
    );
}

#[test]
// test-policy: skip MOSH-99 -- needs the built engine through MOSH_MEDIA_ENGINE; scripts/call-video-bench.mjs runs it with --ignored
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn frame_path() {
    let [engine, _callee] = engines();
    for size @ (width, height) in SIZES {
        let pixels = synthetic(width as usize * height as usize * 4);
        conversions(&engine, size, &pixels);
        transfer(size, &pixels);
        texture(size, &pixels);
    }
}
