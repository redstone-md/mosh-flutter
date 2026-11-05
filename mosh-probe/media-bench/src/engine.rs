//! An engine library behind the mosh_media_* C ABI.
use anyhow::{Context, Result, bail};
use libloading::Library;
use serde_json::Value;
use std::ffi::{CStr, CString, c_char, c_void};

type Create = unsafe extern "C" fn(*const c_char) -> *mut c_void;
type Command = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_char);
type Drop = unsafe extern "C" fn(*mut c_void);
type Receive = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32;
type Copy = unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> i32;

pub const MAX_PACKET: usize = 2007;

pub struct Engine {
    handle: *mut c_void,
    command: Command,
    free: Free,
    drop: Drop,
    receive: Receive,
    copy: Copy,
    _library: Library,
}

impl Engine {
    pub fn load(path: &str, config: &Value) -> Result<Self> {
        // SAFETY: a locally built engine exporting the pinned ABI.
        let library = unsafe { Library::new(path) }?;
        // SAFETY: signatures match mosh-media/engine/src/abi.rs.
        unsafe {
            let create = *library.get::<Create>(b"mosh_media_create\0")?;
            let config = CString::new(config.to_string())?;
            let handle = create(config.as_ptr());
            if handle.is_null() {
                bail!("engine creation failed");
            }
            Ok(Self {
                handle,
                command: *library.get(b"mosh_media_command\0")?,
                free: *library.get(b"mosh_media_free\0")?,
                drop: *library.get(b"mosh_media_drop\0")?,
                receive: *library.get(b"mosh_media_receive\0")?,
                copy: *library.get(b"mosh_media_copy_packet\0")?,
                _library: library,
            })
        }
    }

    pub fn ask(&self, value: &Value) -> Result<Value> {
        let command = CString::new(value.to_string())?;
        // SAFETY: live handle; the result is freed exactly once below.
        let result = unsafe { (self.command)(self.handle, command.as_ptr()) };
        anyhow::ensure!(!result.is_null(), "engine returned null");
        // SAFETY: NUL-terminated buffer owned by the engine until free.
        let text = unsafe { CStr::from_ptr(result) }
            .to_string_lossy()
            .into_owned();
        unsafe { (self.free)(result) };
        let reply: Value = serde_json::from_str(&text).context("engine reply")?;
        if let Some(error) = reply["error"].as_str() {
            bail!("{} failed: {error}", value["action"]);
        }
        Ok(reply)
    }

    pub fn receive(&self, packet: &[u8]) {
        // SAFETY: live handle; the packet stays readable through the call.
        unsafe { (self.receive)(self.handle, packet.as_ptr(), packet.len()) };
    }

    pub fn packet(&self, buffer: &mut [u8; MAX_PACKET]) -> Option<usize> {
        // SAFETY: live handle; the buffer is exclusively writable.
        let length = unsafe { (self.copy)(self.handle, buffer.as_mut_ptr(), buffer.len()) };
        (length > 0).then_some(length as usize)
    }
}

impl std::ops::Drop for Engine {
    fn drop(&mut self) {
        // SAFETY: the handle came from create and is dropped once.
        unsafe { (self.drop)(self.handle) };
    }
}
