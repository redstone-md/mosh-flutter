//! Capture only: no call identities, media keys, audio, engine or network access.
mod cadence;
mod devices;
mod formats;

use anyhow::Context;
use nokhwa::{
    Camera,
    pixel_format::RgbAFormat,
    utils::{CameraFormat, CameraIndex, RequestedFormat, RequestedFormatType},
};
use std::{
    io::{Read, Write},
    time::{Duration, Instant},
};

fn main() {
    if let Err(error) = run() {
        let _ = writeln!(
            std::io::stdout(),
            "{}",
            serde_json::json!({"error":"camera_unavailable"})
        );
        eprintln!("camera capture: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let arguments: Vec<_> = std::env::args().skip(1).collect();
    if arguments.first().is_some_and(|arg| arg == "--list") {
        println!("{}", serde_json::to_string(&devices::list()?)?);
        return Ok(());
    }
    anyhow::ensure!(
        arguments.first().is_some_and(|arg| arg == "--capture") && arguments.len() <= 2,
        "expected --list or --capture [device-id]"
    );
    // EOF is also delivered when the owning process crashes. This thread can
    // exit the helper even while the capture thread is blocked in a driver.
    std::thread::spawn(|| {
        let mut byte = [0; 1];
        while std::io::stdin().read(&mut byte).is_ok_and(|read| read != 0) {}
        std::process::exit(0);
    });
    eprintln!("camera startup: requesting permission");
    permission().context("camera permission")?;
    eprintln!("camera startup: enumerating devices");
    let mut available = devices::list().context("enumerating cameras")?;
    let selected = arguments.get(1).filter(|id| !id.is_empty());
    let index = selected
        .map_or(Some(0), |id| {
            available.iter().position(|device| &device.id == id)
        })
        .filter(|index| *index < available.len())
        .ok_or_else(|| anyhow::anyhow!("camera missing"))?;
    let device = available.remove(index);
    let (mut camera, chosen) = open_camera(device.index)?;
    let mut output = std::io::stdout().lock();
    writeln!(
        output,
        "{}",
        serde_json::json!({"ready":true, "device":device.id,
        "width":chosen.width(), "height":chosen.height(), "requested_fps":chosen.frame_rate()})
    )?;
    output.flush()?;
    capture(&mut camera, &mut output)
}

fn open_camera(index: CameraIndex) -> anyhow::Result<(Camera, CameraFormat)> {
    eprintln!("camera startup: initializing device");
    let mut camera = Camera::new(
        index,
        RequestedFormat::new::<RgbAFormat>(RequestedFormatType::None),
    )
    .context("initializing camera")?;
    let supported = camera
        .compatible_camera_formats()
        .context("enumerating camera formats")?;
    let chosen = formats::choose(supported)?;
    eprintln!("camera startup: configuring {chosen}");
    camera
        .set_camera_requset(RequestedFormat::new::<RgbAFormat>(
            RequestedFormatType::Exact(chosen),
        ))
        .context("setting camera format")?;
    eprintln!("camera startup: opening stream");
    camera.open_stream().context("opening camera stream")?;
    eprintln!("camera startup: stream opened, waiting for first frame");
    Ok((camera, chosen))
}

fn permission() -> anyhow::Result<()> {
    let (send, receive) = std::sync::mpsc::sync_channel(1);
    nokhwa::nokhwa_initialize(move |granted| {
        let _ = send.try_send(granted);
    });
    anyhow::ensure!(
        receive.recv_timeout(Duration::from_secs(60))?,
        "camera permission denied"
    );
    Ok(())
}

fn capture(camera: &mut Camera, output: &mut impl Write) -> anyhow::Result<()> {
    let mut cadence = cadence::Cadence::new(Instant::now());
    let mut first = true;
    loop {
        let acquired = std::time::SystemTime::now();
        let frame = camera.frame().context("reading camera frame")?;
        if !cadence.accept(Instant::now()) {
            continue;
        }
        let resolution = frame.resolution();
        let (width, height) = (resolution.width(), resolution.height());
        anyhow::ensure!(
            width > 0
                && height > 0
                && width <= 1920
                && height <= 1920
                && width as u64 * height as u64 <= 1920 * 1080,
            "camera frame too large"
        );
        let image = frame
            .decode_image::<RgbAFormat>()
            .context("decoding camera frame")?;
        let pixels = image.into_raw();
        anyhow::ensure!(
            pixels.len() == width as usize * height as usize * 4,
            "invalid camera frame"
        );
        let timestamp = frame
            .capture_timestamp()
            .unwrap_or_else(|| {
                acquired
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
            })
            .as_millis() as u64;
        write_frame(output, width, height, &pixels, timestamp)?;
        if first {
            eprintln!("camera first frame written: {width}x{height}");
            first = false;
        }
    }
}

fn write_frame(
    output: &mut impl Write,
    width: u32,
    height: u32,
    pixels: &[u8],
    timestamp: u64,
) -> std::io::Result<()> {
    output.write_all(b"MCP1")?;
    for field in [width, height, pixels.len() as u32] {
        output.write_all(&field.to_be_bytes())?;
    }
    output.write_all(&timestamp.to_be_bytes())?;
    output.write_all(pixels)?;
    output.flush()
}
