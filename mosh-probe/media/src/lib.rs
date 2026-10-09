//! Isolated candidate ABI. No RingRTC types or dependencies enter mosh-core.
mod endpoint;
#[cfg(test)]
mod frame_api_tests;
mod frames;
mod negotiation;
mod observer;

use endpoint::Endpoint;
use negotiation::Description;
use ringrtc::webrtc::injectable_network::Packet;
use serde_json::{Value, json};
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
    mpsc::{Receiver, sync_channel},
};
use std::time::{Duration, Instant};

struct Engine {
    endpoint: Endpoint,
    packets: Receiver<Packet>,
    role: String,
    started: bool,
    tick: u8,
    next_frame: Instant,
    next_stats: Instant,
    remote_ready: bool,
    pending_candidates: Vec<String>,
    queue_dropped: std::sync::Arc<AtomicU64>,
}

impl Engine {
    fn new(role: u8) -> ringrtc::common::Result<Self> {
        let role = if role == 0 { "caller" } else { "callee" };
        let (sender, packets) = sync_channel(128);
        let queue_dropped = std::sync::Arc::new(AtomicU64::new(0));
        let measured = queue_dropped.clone();
        let endpoint = Endpoint::new(role, move |packet| {
            if sender.try_send(packet).is_err() {
                measured.fetch_add(1, Ordering::Relaxed);
            }
        })?;
        Ok(Self {
            endpoint,
            packets,
            role: role.into(),
            started: false,
            tick: 0,
            next_frame: Instant::now(),
            next_stats: Instant::now(),
            remote_ready: false,
            pending_candidates: Vec::new(),
            queue_dropped,
        })
    }

    fn command(&mut self, value: Value) -> ringrtc::common::Result<Value> {
        match value["action"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("missing action"))?
        {
            "offer" => Ok(serde_json::to_value(Description::create(
                &self.endpoint.pc,
                true,
            )?)?),
            "answer" => Ok(serde_json::to_value(Description::create(
                &self.endpoint.pc,
                false,
            )?)?),
            "remote" => {
                serde_json::from_value::<Description>(value["description"].clone())?
                    .install(&self.endpoint.pc, false)?;
                self.remote_ready = true;
                Ok(json!({"ok":true}))
            }
            "start" => {
                self.endpoint.enable()?;
                self.started = true;
                Ok(json!({"ok":true}))
            }
            "tick" => self.pump(value),
            "snapshot" => Ok(self.snapshot()),
            _ => anyhow::bail!("unknown action"),
        }
    }

    fn pump(&mut self, value: Value) -> ringrtc::common::Result<Value> {
        for candidate in value["candidates"].as_array().into_iter().flatten() {
            if self.pending_candidates.len() >= 32 {
                anyhow::bail!("candidate queue exceeded");
            }
            self.pending_candidates.push(
                candidate
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("invalid candidate"))?
                    .into(),
            );
        }
        if self.remote_ready {
            for candidate in self.pending_candidates.drain(..) {
                self.endpoint.pc.add_ice_candidate_from_sdp(&candidate)?;
            }
        }
        for data in value["packets"].as_array().into_iter().flatten() {
            let bytes: Vec<u8> = serde_json::from_value(data.clone())?;
            if let Some(packet) = decode(&bytes, &self.role) {
                self.endpoint.network.receive_udp(packet);
            }
        }
        if self.started && Instant::now() >= self.next_frame {
            self.endpoint.push(self.tick);
            self.tick = self.tick.wrapping_add(1);
            self.next_frame += Duration::from_nanos(1_000_000_000 / 30);
            if self.next_frame < Instant::now() {
                self.next_frame = Instant::now() + Duration::from_nanos(1_000_000_000 / 30);
            }
        }
        if Instant::now() >= self.next_stats {
            self.endpoint.pc.get_stats(&self.endpoint.stats)?;
            self.next_stats = Instant::now() + Duration::from_secs(1);
        }
        let packets: Vec<_> = self.packets.try_iter().take(128).map(encode).collect();
        let candidates: Vec<_> = self.endpoint.candidates.try_iter().collect();
        Ok(json!({"packets": packets, "candidates": candidates}))
    }

    fn snapshot(&self) -> Value {
        let mut measurements = self.endpoint.measurements.snapshot();
        measurements["engine_queue_dropped"] = self.queue_dropped.load(Ordering::Relaxed).into();
        measurements
    }
}

fn encode(packet: Packet) -> Vec<u8> {
    let mut bytes = b"MV1".to_vec();
    bytes.extend(packet.source.port().to_be_bytes());
    bytes.extend(packet.dest.port().to_be_bytes());
    bytes.extend(packet.data);
    bytes
}

fn decode(bytes: &[u8], role: &str) -> Option<Packet> {
    if bytes.len() < 7 || bytes.len() > 2007 || &bytes[..3] != b"MV1" {
        return None;
    }
    let (source, dest) = if role == "caller" {
        ("192.0.2.2", "192.0.2.1")
    } else {
        ("192.0.2.1", "192.0.2.2")
    };
    Some(Packet {
        source: (
            source.parse::<std::net::IpAddr>().ok()?,
            u16::from_be_bytes([bytes[3], bytes[4]]),
        )
            .into(),
        dest: (
            dest.parse::<std::net::IpAddr>().ok()?,
            u16::from_be_bytes([bytes[5], bytes[6]]),
        )
            .into(),
        data: bytes[7..].to_vec(),
    })
}

/// Create the isolated synthetic-media fixture. Returns null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn mosh_media_probe_create(role: u8) -> *mut std::ffi::c_void {
    catch_unwind(AssertUnwindSafe(|| match Engine::new(role) {
        Ok(engine) => Box::into_raw(Box::new(Mutex::new(engine))).cast(),
        Err(error) => {
            eprintln!("media probe creation failed: {error}");
            std::ptr::null_mut()
        }
    }))
    .unwrap_or(std::ptr::null_mut())
}

/// Execute one bounded test command; release its result using mosh_media_probe_free.
/// # Safety
/// Handle must be live; command must point to a NUL-terminated UTF-8 C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_probe_command(
    handle: *mut std::ffi::c_void,
    command: *const c_char,
) -> *mut c_char {
    if handle.is_null() || command.is_null() {
        return std::ptr::null_mut();
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the host exclusively owns the live handle and retains command for this call.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        // SAFETY: the caller retains a valid NUL-terminated command for this call.
        let bytes = unsafe { CStr::from_ptr(command) }.to_bytes();
        engine
            .lock()
            .map_err(|_| anyhow::anyhow!("candidate state poisoned"))?
            .command(serde_json::from_slice(bytes)?)
    }))
    .unwrap_or_else(|_| Err(anyhow::anyhow!("candidate command panicked")));
    let value = result.unwrap_or_else(|error| json!({"error":error.to_string()}));
    CString::new(value.to_string()).unwrap().into_raw()
}

/// # Safety
/// Result must come from mosh_media_probe_command and be freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_probe_free(result: *mut c_char) {
    if !result.is_null() {
        // SAFETY: the caller returns exclusive ownership of this library's allocation.
        drop(unsafe { CString::from_raw(result) });
    }
}

/// Copy the latest decoded frame. Returns 0=no newer frame, 1=copied,
/// 2=short buffer (info reports required bytes), -1=invalid arguments/failure.
/// # Safety
/// Handle must be live. `info` is aligned, writable and disjoint from `rgba`.
/// A nonempty `rgba` is writable for `capacity` bytes. Neither buffer is accessed
/// concurrently. No call may run concurrently with drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_probe_copy_frame(
    handle: *mut std::ffi::c_void,
    after: u64,
    rgba: *mut u8,
    capacity: usize,
    info: *mut frames::FrameInfo,
) -> i32 {
    if handle.is_null()
        || info.is_null()
        || capacity > frames::MAX_RGBA_BYTES
        || (capacity != 0 && rgba.is_null())
    {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains the live handle until this synchronous copy ends.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let Ok(engine) = engine.lock() else { return -1 };
        let pixels = if capacity == 0 {
            &mut []
        } else {
            // SAFETY: caller guarantees capacity writable bytes and no aliases.
            unsafe { std::slice::from_raw_parts_mut(rgba, capacity) }
        };
        let mut metadata = frames::FrameInfo::default();
        let status = engine
            .endpoint
            .measurements
            .frames
            .copy(after, pixels, &mut metadata);
        // SAFETY: caller provides a disjoint, aligned writable metadata allocation.
        unsafe { info.write(metadata) };
        status
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle must come from create, with no concurrent commands, and be dropped once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_probe_drop(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        // SAFETY: the caller returns the exclusively owned engine allocation.
        let _ = catch_unwind(AssertUnwindSafe(|| {
            drop(unsafe { Box::from_raw(handle.cast::<Mutex<Engine>>()) })
        }));
    }
}
