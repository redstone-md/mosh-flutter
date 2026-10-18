//! The owner can kill and reap a blocked driver without blocking audio.
use super::{
    library::{artifact, MAX_RGBA},
    types::Device,
};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use std::{
    io::{BufRead, BufReader, Read},
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub(crate) struct Captured {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub received: Instant,
    pub source_age_ms: u32,
}

#[derive(Default)]
struct Output {
    ready: Option<Instant>,
    frame: Option<Arc<Captured>>,
    done: bool,
    error: Option<String>,
}

pub(crate) struct Capture {
    child: Child,
    output: Arc<Mutex<Output>>,
    started: Instant,
    stderr: Option<JoinHandle<Vec<u8>>>,
    failure: Option<String>,
}

impl Capture {
    pub fn start(id: Option<&str>) -> Result<Self, String> {
        let mut command = helper()?;
        command.arg("--capture");
        if let Some(id) = id {
            command.arg(id);
        }
        let mut child = command
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| error.to_string())?;
        let stdout = child.stdout.take().ok_or("missing camera output")?;
        let stderr = child.stderr.take().ok_or("missing camera diagnostics")?;
        let stderr = Some(std::thread::spawn(move || read_stderr(stderr)));
        let output = Arc::new(Mutex::new(Output::default()));
        let sink = output.clone();
        std::thread::spawn(move || {
            let result = read_capture(BufReader::new(stdout), &sink);
            let mut output = sink.lock().unwrap_or_else(|error| error.into_inner());
            output.error = result.err();
            output.done = true;
        });
        Ok(Self {
            child,
            output,
            started: Instant::now(),
            stderr,
            failure: None,
        })
    }

    pub fn failed(&mut self) -> bool {
        let status = self.child.try_wait();
        let output = self
            .output
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.failure = if output.done {
            Some(format!(
                "output ended: {}",
                output.error.as_deref().unwrap_or("EOF")
            ))
        } else if let Ok(Some(status)) = &status {
            Some(format!("helper exited: {status}"))
        } else if let Err(error) = status {
            Some(format!("waiting for helper: {error}"))
        } else if output.ready.map_or_else(
            || self.started.elapsed() > Duration::from_secs(65),
            |ready| {
                output
                    .frame
                    .as_ref()
                    .map_or(ready, |frame| frame.received)
                    .elapsed()
                    > Duration::from_secs(4)
            },
        ) {
            Some(
                if output.ready.is_some() {
                    "no camera frames for 4 seconds"
                } else {
                    "camera startup exceeded 65 seconds"
                }
                .to_string(),
            )
        } else {
            None
        };
        self.failure.is_some()
    }

    pub fn frame(&self, after: u64) -> Option<Arc<Captured>> {
        self.output
            .lock()
            .ok()?
            .frame
            .as_ref()
            .filter(|frame| frame.sequence > after)
            .cloned()
    }
}
impl Drop for Capture {
    fn drop(&mut self) {
        let exited = self.child.try_wait().ok().flatten();
        drop(self.child.stdin.take());
        if exited.is_none() {
            let _ = self.child.kill();
        }
        let status = self.child.wait();
        let stderr = self
            .stderr
            .take()
            .and_then(|reader| reader.join().ok())
            .unwrap_or_default();
        let level = if self.failure.is_some() {
            LogLevel::Warn
        } else {
            LogLevel::Info
        };
        let message = format!(
            "camera capture stopped: reason={}; exit={status:?}; terminated_by_owner={}; stderr={}",
            self.failure.as_deref().unwrap_or("camera disabled"),
            exited.is_none(),
            String::from_utf8_lossy(&stderr).trim(),
        );
        dlog::write(level, kinds::CALL, "", &message);
    }
}

// Drain continuously so a verbose native driver cannot block capture. Keep
// only its last 8 KiB; stdout contains pixels and never enters the field log.
fn read_stderr(mut reader: impl Read) -> Vec<u8> {
    let mut tail = Vec::new();
    let mut chunk = [0; 1024];
    loop {
        match reader.read(&mut chunk) {
            Ok(0) => break,
            Ok(count) => {
                tail.extend_from_slice(&chunk[..count]);
                if tail.len() > 8192 {
                    tail.drain(..tail.len() - 8192);
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
    tail
}

fn read_capture(mut reader: impl BufRead, output: &Mutex<Output>) -> Result<(), String> {
    let mut initial = Vec::new();
    Read::by_ref(&mut reader)
        .take(8193)
        .read_until(b'\n', &mut initial)
        .map_err(|e| e.to_string())?;
    if initial.len() > 8192 || initial.last() != Some(&b'\n') {
        return Err("invalid camera readiness".into());
    }
    let ready: serde_json::Value = serde_json::from_slice(&initial).map_err(|e| e.to_string())?;
    if ready["ready"] != true {
        return Err("camera is not ready".into());
    }
    output.lock().map_err(|_| "camera state poisoned")?.ready = Some(Instant::now());
    let mut sequence = 0u64;
    loop {
        let mut header = [0; 24];
        reader.read_exact(&mut header).map_err(|e| e.to_string())?;
        let (width, height, length, timestamp) =
            header_fields(&header).ok_or("invalid camera frame")?;
        let mut pixels = vec![0; length];
        reader.read_exact(&mut pixels).map_err(|e| e.to_string())?;
        sequence = sequence.saturating_add(1);
        output.lock().map_err(|_| "camera state poisoned")?.frame = Some(Arc::new(Captured {
            sequence,
            width,
            height,
            pixels,
            received: Instant::now(),
            source_age_ms: wall_ms().saturating_sub(timestamp).min(u32::MAX as u64) as u32,
        }));
    }
}

fn header_fields(header: &[u8; 24]) -> Option<(u32, u32, usize, u64)> {
    if &header[..4] != b"MCP1" {
        return None;
    }
    let width = u32::from_be_bytes(header[4..8].try_into().ok()?);
    let height = u32::from_be_bytes(header[8..12].try_into().ok()?);
    let length = u32::from_be_bytes(header[12..16].try_into().ok()?) as usize;
    if width == 0
        || height == 0
        || width > 1920
        || height > 1920
        || length > MAX_RGBA
        || width as u64 * height as u64 * 4 != length as u64
    {
        return None;
    }
    Some((
        width,
        height,
        length,
        u64::from_be_bytes(header[16..].try_into().ok()?),
    ))
}

pub(crate) fn wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn helper() -> Result<Command, String> {
    let name = if cfg!(target_os = "windows") {
        "mosh-camera-capture.exe"
    } else {
        "mosh-camera-capture"
    };
    Ok(helper_command(artifact("MOSH_CAMERA_CAPTURE", name)?))
}

fn helper_command(executable: std::path::PathBuf) -> Command {
    let mut command = Command::new(executable);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // Both enumeration and capture are background console executables.
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    command
}

pub(crate) struct Query {
    child: Child,
    started: Instant,
}
impl Query {
    pub fn start() -> Result<Self, String> {
        let child = helper()?
            .arg("--list")
            .stdin(Stdio::null())
            .spawn()
            .map_err(|error| error.to_string())?;
        Ok(Self {
            child,
            started: Instant::now(),
        })
    }
    pub fn poll(&mut self) -> Option<Result<Vec<Device>, String>> {
        let finished = match self.child.try_wait() {
            Ok(status) => status,
            Err(error) => return Some(Err(format!("camera enumeration wait: {error}"))),
        };
        if finished.is_none() && self.started.elapsed() < Duration::from_secs(3) {
            return None;
        }
        let Some(status) = finished else {
            return Some(Err("camera enumeration timed out".into()));
        };
        if !status.success() {
            return Some(Err(format!("camera enumeration exited: {status}")));
        }
        let Some(stdout) = self.child.stdout.take() else {
            return Some(Err("missing camera enumeration output".into()));
        };
        Some(read_devices(stdout))
    }
}
impl Drop for Query {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn read_devices(reader: impl Read) -> Result<Vec<Device>, String> {
    let mut bytes = Vec::new();
    reader
        .take(65_537)
        .read_to_end(&mut bytes)
        .map_err(|error| error.to_string())?;
    if bytes.len() > 65_536 {
        return Err("camera enumeration output too large".into());
    }
    let devices: Vec<Device> = serde_json::from_slice(&bytes).map_err(|error| error.to_string())?;
    Ok(devices
        .into_iter()
        .filter(|device| {
            !device.id.is_empty() && device.id.len() <= 4096 && device.name.len() <= 512
        })
        .take(32)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(windows)]
    #[test]
    fn camera_helpers_have_no_console_window() {
        // Use a console executable to observe the actual process-creation flags.
        let script = r#"
Add-Type -Name CameraConsole -Namespace Mosh -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
[Mosh.CameraConsole]::GetConsoleWindow().ToInt64()
"#;
        let output = helper_command("powershell.exe".into())
            .args(["-NoProfile", "-NonInteractive", "-Command", script])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "0");
    }
    #[test]
    fn validates_camera_header_before_allocating_and_never_formats_pixels() {
        let mut header = [0; 24];
        header[..4].copy_from_slice(b"MCP1");
        header[4..8].copy_from_slice(&1280u32.to_be_bytes());
        header[8..12].copy_from_slice(&720u32.to_be_bytes());
        header[12..16].copy_from_slice(&(1280u32 * 720 * 4).to_be_bytes());
        header[16..].copy_from_slice(&1234u64.to_be_bytes());
        assert_eq!(
            header_fields(&header),
            Some((1280, 720, 1280 * 720 * 4, 1234))
        );
        header[4..8].copy_from_slice(&u32::MAX.to_be_bytes());
        assert!(header_fields(&header).is_none());
    }
}
