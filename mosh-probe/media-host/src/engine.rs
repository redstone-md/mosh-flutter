//! Host-owned candidate lifetime, loaded in the main process via an isolated ABI.
use crate::ProbeResult;
use crate::frames::FrameInfo;
use libloading::Library;
use serde_json::Value;
use std::ffi::{CStr, CString, c_char, c_void};

type Create = unsafe extern "C" fn(u8) -> *mut c_void;
type Command = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_char);
type DropEngine = unsafe extern "C" fn(*mut c_void);
type CopyFrame = unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize, *mut FrameInfo) -> i32;

pub struct Engine {
    handle: *mut c_void,
    command: Command,
    free: Free,
    drop_engine: DropEngine,
    copy_frame: CopyFrame,
    _library: Library,
}

impl Engine {
    pub fn new(role: &str) -> ProbeResult<Self> {
        let path = std::env::var("MOSH_MEDIA_ENGINE")?;
        // SAFETY: explicitly chosen, locally built candidate library and its pinned ABI.
        let library = unsafe { Library::new(path) }?;
        // SAFETY: signatures match the candidate exports; library remains owned by Engine.
        let (create, command, free, drop_engine, copy_frame) = unsafe {
            (
                *library.get::<Create>(b"mosh_media_probe_create\0")?,
                *library.get::<Command>(b"mosh_media_probe_command\0")?,
                *library.get::<Free>(b"mosh_media_probe_free\0")?,
                *library.get::<DropEngine>(b"mosh_media_probe_drop\0")?,
                *library.get::<CopyFrame>(b"mosh_media_probe_copy_frame\0")?,
            )
        };
        // SAFETY: create has no pointer arguments; caller=0 and callee=1.
        let handle = unsafe { create(u8::from(role == "callee")) };
        if handle.is_null() {
            return Err("candidate engine creation failed".into());
        }
        Ok(Self {
            handle,
            command,
            free,
            drop_engine,
            copy_frame,
            _library: library,
        })
    }

    pub fn ask(&self, value: Value) -> ProbeResult<Value> {
        let command = CString::new(value.to_string())?;
        // SAFETY: handle is live, command remains valid, no command runs concurrently.
        let result = unsafe { (self.command)(self.handle, command.as_ptr()) };
        if result.is_null() {
            return Err("candidate returned null".into());
        }
        // SAFETY: command returns a NUL-terminated buffer valid until free.
        let value = serde_json::from_slice::<Value>(unsafe { CStr::from_ptr(result) }.to_bytes());
        // SAFETY: return this allocation to the same library exactly once, even on parse error.
        unsafe { (self.free)(result) };
        let value = value?;
        if let Some(error) = value["error"].as_str() {
            return Err(error.to_owned().into());
        }
        Ok(value)
    }

    pub fn copy_frame(&self, after: u64, pixels: &mut [u8]) -> ProbeResult<Option<FrameInfo>> {
        let mut info = FrameInfo::default();
        // SAFETY: Engine owns the live handle/library. Both output allocations
        // are writable, disjoint and retained until this synchronous copy ends.
        let status = unsafe {
            (self.copy_frame)(
                self.handle,
                after,
                pixels.as_mut_ptr(),
                pixels.len(),
                &mut info,
            )
        };
        match status {
            0 => Ok(None),
            1 => Ok(Some(info)),
            _ => Err("candidate frame copy failed".into()),
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        // SAFETY: Engine exclusively owns the handle; the library has not unloaded.
        unsafe { (self.drop_engine)(self.handle) };
    }
}
