//! What bringing one camera frame to I420 costs, per camera format and
//! frame size. It prints rows for `scripts/call-video-bench.mjs` and asserts
//! no speed.
use crate::{i420::Converter, jpeg};
use nokhwa::utils::FrameFormat;
use std::time::{Duration, Instant};

const SIZES: [(u32, u32); 3] = [(640, 360), (1280, 720), (1920, 1080)];
const WARM_UPS: usize = 5;
const RUNS: usize = 60;

/// Bytes that vary across the frame, so no conversion sees a flat picture.
fn synthetic(length: usize) -> Vec<u8> {
    (0..length).map(|i| ((i * 31) >> 3) as u8).collect()
}

/// Sensor grain: xorshift bytes, the same on every run.
fn noise(length: usize) -> Vec<u8> {
    let mut state = 0x9E37_79B9_7F4A_7C15u64;
    (0..length)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            (state >> 32) as u8
        })
        .collect()
}

/// Prints the median of `RUNS` timed calls of `run` after `WARM_UPS` untimed ones.
fn report(case: &str, (width, height): (u32, u32), mut run: impl FnMut()) {
    let mut times: Vec<Duration> = (0..WARM_UPS + RUNS)
        .map(|_| {
            let started = Instant::now();
            run();
            started.elapsed()
        })
        .skip(WARM_UPS)
        .collect();
    times.sort();
    let ms = times[RUNS / 2].as_secs_f64() * 1000.0;
    println!(
        "call-video-bench {}",
        serde_json::json!({"case": case, "width": width, "height": height, "ms": ms})
    );
}

#[test]
// test-policy: skip MOSH-96 -- a measurement without assertions; scripts/call-video-bench.mjs runs it with --ignored
#[ignore = "A measurement; scripts/call-video-bench.mjs runs it"]
fn camera_formats() {
    for size @ (width, height) in SIZES {
        let pixels = width as usize * height as usize;
        // Webcams send 4:2:2. Gradients under sensor grain compress to about
        // a webcam frame's size, 85 KiB at 720p.
        let grain = noise(pixels);
        let colour = |i: usize| {
            let (x, y) = (i % width as usize, i / width as usize);
            let grain = grain[i] % 12;
            [(x / 5) as u8 + grain, (y / 5) as u8 + grain, 96 + grain]
        };
        let mjpeg = jpeg::encode(width as usize, height as usize, (2, 1), 85.0, colour);
        for (name, format, frame) in [
            ("NV12", FrameFormat::NV12, synthetic(pixels * 3 / 2)),
            ("YUYV", FrameFormat::YUYV, synthetic(pixels * 2)),
            ("MJPEG 4:2:2", FrameFormat::MJPEG, mjpeg),
        ] {
            let mut converter = Converter::default();
            report(&format!("camera {name} to I420 (helper)"), size, || {
                converter.convert(format, size, &frame).expect("converted");
            });
        }
    }
}
