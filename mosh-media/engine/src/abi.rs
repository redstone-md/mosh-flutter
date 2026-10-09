//! The loading process retains every buffer through its synchronous call.
//! Create, command and drop an engine on one owner thread; Windows COM is thread-bound.
use crate::{
    engine::{Config, Engine, MAX_PACKET},
    frames::{FrameInfo, MAX_RGBA_BYTES},
};
use serde_json::json;
use std::{
    ffi::{CStr, CString, c_char, c_void},
    panic::{AssertUnwindSafe, catch_unwind},
    sync::Mutex,
};

/// # Safety
/// Config is a NUL-terminated JSON string retained through this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_create(config: *const c_char) -> *mut c_void {
    if config.is_null() {
        return std::ptr::null_mut();
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains a valid C string through this synchronous call.
        let bytes = unsafe { CStr::from_ptr(config) }.to_bytes();
        if bytes.len() > 4096 {
            return std::ptr::null_mut();
        }
        let engine = serde_json::from_slice::<Config>(bytes)
            .map_err(anyhow::Error::from)
            .and_then(Engine::new);
        match engine {
            Ok(engine) => Box::into_raw(Box::new(Mutex::new(engine))).cast(),
            Err(error) => {
                eprintln!("native media creation failed: {error}");
                std::ptr::null_mut()
            }
        }
    }))
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// Handle is live; command is a retained NUL-terminated C string. Free the result once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_command(
    handle: *mut c_void,
    command: *const c_char,
) -> *mut c_char {
    if handle.is_null() || command.is_null() {
        return std::ptr::null_mut();
    }
    let value = catch_unwind(AssertUnwindSafe(|| -> anyhow::Result<_> {
        // SAFETY: caller retains both the owned handle and C string until return.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let bytes = unsafe { CStr::from_ptr(command) }.to_bytes();
        anyhow::ensure!(bytes.len() <= 65_536, "media command too large");
        engine
            .lock()
            .map_err(|_| anyhow::anyhow!("media state poisoned"))?
            .command(serde_json::from_slice(bytes)?)
    }))
    .unwrap_or_else(|_| Err(anyhow::anyhow!("native media command panicked")))
    .unwrap_or_else(|error| json!({"error": error.to_string()}));
    CString::new(value.to_string())
        .expect("JSON contains no NUL")
        .into_raw()
}

/// # Safety
/// Result comes from this library and is returned exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_free(result: *mut c_char) {
    if !result.is_null() {
        // SAFETY: caller returns exclusive ownership of this library's allocation.
        drop(unsafe { CString::from_raw(result) });
    }
}

/// # Safety
/// Handle is live; data is readable for length bytes. No concurrent drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_receive(
    handle: *mut c_void,
    data: *const u8,
    length: usize,
) -> i32 {
    if handle.is_null() || data.is_null() || !(7..=MAX_PACKET).contains(&length) {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains the live handle and readable packet for this call.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let bytes = unsafe { std::slice::from_raw_parts(data, length) };
        engine
            .lock()
            .map_or(-1, |engine| i32::from(engine.receive(bytes)))
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle is live; data is writable for capacity bytes. No concurrent drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_copy_packet(
    handle: *mut c_void,
    data: *mut u8,
    capacity: usize,
) -> i32 {
    if handle.is_null() || data.is_null() || capacity > MAX_PACKET {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains the handle and an exclusively writable packet buffer.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let bytes = unsafe { std::slice::from_raw_parts_mut(data, capacity) };
        engine
            .lock()
            .map_or(-1, |mut engine| engine.copy_packet(bytes))
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle is live; data is readable for length bytes. No concurrent drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_packet_priority(
    handle: *mut c_void,
    data: *const u8,
    length: usize,
) -> i32 {
    if handle.is_null() || data.is_null() || !(7..=MAX_PACKET).contains(&length) {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: retain the handle and readable packet until this synchronous call ends.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let bytes = unsafe { std::slice::from_raw_parts(data, length) };
        engine
            .lock()
            .map_or(-1, |engine| i32::from(engine.priority(bytes)))
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle is live; RGBA is readable for length bytes. No concurrent drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_push_rgba(
    handle: *mut c_void,
    width: u32,
    height: u32,
    rgba: *const u8,
    length: usize,
) -> i32 {
    if handle.is_null() || rgba.is_null() || length > MAX_RGBA_BYTES {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains the handle and readable packed RGBA buffer.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let pixels = unsafe { std::slice::from_raw_parts(rgba, length) };
        engine.lock().map_or(-1, |engine| {
            if engine.push_rgba(width, height, pixels).is_ok() {
                1
            } else {
                -1
            }
        })
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle is live; info is aligned/writable and disjoint from RGBA. RGBA is
/// exclusively writable for capacity bytes. No concurrent drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_copy_frame(
    handle: *mut c_void,
    after: u64,
    rgba: *mut u8,
    capacity: usize,
    info: *mut FrameInfo,
) -> i32 {
    if handle.is_null()
        || info.is_null()
        || capacity > MAX_RGBA_BYTES
        || (capacity != 0 && rgba.is_null())
    {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains the live handle and disjoint writable output allocations.
        let engine = unsafe { &*handle.cast::<Mutex<Engine>>() };
        let pixels = if capacity == 0 {
            &mut []
        } else {
            unsafe { std::slice::from_raw_parts_mut(rgba, capacity) }
        };
        let Ok(engine) = engine.lock() else {
            return -1;
        };
        let mut metadata = FrameInfo::default();
        let status = engine
            .endpoint
            .measurements
            .frames
            .copy(after, pixels, &mut metadata);
        // SAFETY: caller provides a retained aligned writable metadata allocation.
        unsafe { info.write(metadata) };
        status
    }))
    .unwrap_or(-1)
}

/// # Safety
/// Handle comes from create and is dropped once after all calls have returned.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_drop(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: caller returns exclusive ownership of the engine allocation.
        let _ = catch_unwind(AssertUnwindSafe(|| {
            drop(unsafe { Box::from_raw(handle.cast::<Mutex<Engine>>()) })
        }));
    }
}
