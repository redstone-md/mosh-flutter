use super::Captured;
use crate::{
    android::media::command,
    native_call::{library, types::Device},
};
use jni::{
    objects::{JByteBuffer, JClass},
    EnvUnowned,
};
use serde_json::json;
use std::{
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    time::{Duration, Instant},
};

struct Output {
    generation: u64,
    started: Instant,
    failed: bool,
    sequence: u64,
    frame: Option<Arc<Captured>>,
}
static OUTPUT: Mutex<Option<Output>> = Mutex::new(None);
static GENERATION: AtomicU64 = AtomicU64::new(0);

pub(crate) struct Capture(u64);
impl Capture {
    pub fn start(id: Option<&str>) -> Result<Self, String> {
        let generation = GENERATION.fetch_add(1, Ordering::Relaxed) + 1;
        *OUTPUT.lock().map_err(|_| "camera state poisoned")? = Some(Output {
            generation,
            started: Instant::now(),
            failed: false,
            sequence: 0,
            frame: None,
        });
        let capture = Self(generation);
        command(json!({"action":"cameraStart", "id":id, "generation":generation}))?;
        Ok(capture)
    }
    pub fn failed(&mut self) -> bool {
        let state = OUTPUT.lock().unwrap_or_else(|error| error.into_inner());
        let Some(state) = state.as_ref().filter(|state| state.generation == self.0) else {
            return true;
        };
        state.failed
            || state.frame.as_ref().map_or_else(
                || state.started.elapsed() > Duration::from_secs(10),
                |frame| frame.received.elapsed() > Duration::from_secs(4),
            )
    }
    pub fn frame(&self, after: u64) -> Option<Arc<Captured>> {
        let state = OUTPUT.lock().ok()?;
        state
            .as_ref()?
            .frame
            .as_ref()
            .filter(|frame| frame.sequence > after)
            .cloned()
    }
}
impl Drop for Capture {
    fn drop(&mut self) {
        let mut state = OUTPUT.lock().unwrap_or_else(|error| error.into_inner());
        if state
            .as_ref()
            .is_some_and(|state| state.generation == self.0)
        {
            *state = None; // Fence callbacks before asking Java to release the camera.
            drop(state);
            let _ = command(json!({"action":"cameraStop"}));
        }
    }
}

pub(crate) struct Query(mpsc::Receiver<Result<Vec<Device>, String>>, Instant);
impl Query {
    pub fn start() -> Result<Self, String> {
        static RUNNING: AtomicBool = AtomicBool::new(false);
        if RUNNING.swap(true, Ordering::Acquire) {
            return Err("camera inventory still running".into());
        }
        let (tx, rx) = mpsc::sync_channel(1);
        std::thread::spawn(move || {
            let result = command(json!({"action":"cameras"})).and_then(|value| {
                serde_json::from_value(value["cameras"].clone()).map_err(|error| error.to_string())
            });
            let _ = tx.send(result);
            RUNNING.store(false, Ordering::Release);
        });
        Ok(Self(rx, Instant::now()))
    }
    pub fn poll(&mut self) -> Option<Result<Vec<Device>, String>> {
        match self.0.try_recv() {
            Ok(result) => Some(result),
            Err(mpsc::TryRecvError::Empty) if self.1.elapsed() < Duration::from_secs(3) => None,
            Err(_) => Some(Err("Android camera enumeration did not complete".into())),
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshCallCamera_cameraFailed(
    _env: EnvUnowned<'_>,
    _class: JClass<'_>,
    generation: i64,
) {
    if let Ok(mut state) = OUTPUT.lock() {
        if let Some(state) = state
            .as_mut()
            .filter(|state| state.generation == generation as u64)
        {
            state.failed = true;
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshCallCamera_cameraFrame<'caller>(
    mut unowned: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    generation: i64,
    width: i32,
    height: i32,
    buffer: JByteBuffer<'caller>,
) {
    unowned
        .with_env(|env| -> Result<(), jni::errors::Error> {
            if !OUTPUT.lock().is_ok_and(|state| {
                state
                    .as_ref()
                    .is_some_and(|state| state.generation == generation as u64 && !state.failed)
            }) {
                return Ok(());
            }
            let (w, h) = (width as u32, height as u32);
            let Some(length) = library::i420_size(w, h) else {
                return Ok(());
            };
            if env.get_direct_buffer_capacity(&buffer)? < length {
                return Ok(());
            }
            let data = env.get_direct_buffer_address(&buffer)?;
            // SAFETY: Java retains this direct packed I420 buffer until the synchronous
            // callback returns. Capacity and dimensions are validated before reading.
            let planar = unsafe { std::slice::from_raw_parts(data, length) };
            let Ok(pixels) = library::i420_to_rgba(w, h, planar) else {
                return Ok(());
            };
            publish(generation as u64, w, h, pixels);
            Ok(())
        })
        .resolve::<jni::errors::ThrowRuntimeExAndDefault>();
}

fn publish(generation: u64, width: u32, height: u32, pixels: Vec<u8>) {
    let mut output = OUTPUT.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(output) = output
        .as_mut()
        .filter(|state| state.generation == generation && !state.failed)
    {
        output.sequence += 1;
        output.frame = Some(Arc::new(Captured {
            sequence: output.sequence,
            width,
            height,
            pixels,
            received: Instant::now(),
            source_age_ms: 0,
        }));
    }
}
