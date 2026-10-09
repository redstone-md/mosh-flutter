//! Load and use the isolated graph on its owning thread; no raw handle is Send.
use super::types::Binding;
use libloading::Library;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_void, CStr, CString},
    path::PathBuf,
};

pub const MAX_RGBA: usize = 1920 * 1080 * 4;
pub const MAX_PACKET: usize = 2007;
type Create = unsafe extern "C" fn(*const c_char) -> *mut c_void;
type Command = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_char);
type DropEngine = unsafe extern "C" fn(*mut c_void);
type Receive = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32;
type CopyPacket = unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> i32;
type Push = unsafe extern "C" fn(*mut c_void, u32, u32, *const u8, usize) -> i32;
type CopyFrame = unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize, *mut FrameInfo) -> i32;

#[repr(C)]
#[derive(Default)]
pub(crate) struct FrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: u32,
    pub age_ms: u32,
}

pub(crate) struct Engine {
    handle: *mut c_void,
    command: Command,
    free: Free,
    drop_engine: DropEngine,
    receive: Receive,
    priority: Receive,
    copy_packet: CopyPacket,
    push: Push,
    copy_frame: CopyFrame,
    _library: Library,
}

impl Engine {
    pub fn new(binding: &Binding, caller: bool) -> Result<Self, String> {
        let config =
            CString::new(json!({"binding":binding,"caller":caller}).to_string()).map_err(error)?;
        // SAFETY: load only the packaged or explicitly selected local native artifact.
        let library = unsafe { Library::new(artifact("MOSH_MEDIA_ENGINE", library_name())?) }
            .map_err(error)?;
        // SAFETY: these signatures match the pinned Mosh ABI. Retain the library through drop.
        let (create, command, free, drop_engine, receive, priority, copy_packet, push, copy_frame) = unsafe {
            (
                *library
                    .get::<Create>(b"mosh_media_create\0")
                    .map_err(error)?,
                *library
                    .get::<Command>(b"mosh_media_command\0")
                    .map_err(error)?,
                *library.get::<Free>(b"mosh_media_free\0").map_err(error)?,
                *library
                    .get::<DropEngine>(b"mosh_media_drop\0")
                    .map_err(error)?,
                *library
                    .get::<Receive>(b"mosh_media_receive\0")
                    .map_err(error)?,
                *library
                    .get::<Receive>(b"mosh_media_packet_priority\0")
                    .map_err(error)?,
                *library
                    .get::<CopyPacket>(b"mosh_media_copy_packet\0")
                    .map_err(error)?,
                *library
                    .get::<Push>(b"mosh_media_push_rgba\0")
                    .map_err(error)?,
                *library
                    .get::<CopyFrame>(b"mosh_media_copy_frame\0")
                    .map_err(error)?,
            )
        };
        // SAFETY: config is retained until this synchronous create returns.
        let handle = unsafe { create(config.as_ptr()) };
        if handle.is_null() {
            return Err("native media creation failed".into());
        }
        Ok(Self {
            handle,
            command,
            free,
            drop_engine,
            receive,
            priority,
            copy_packet,
            push,
            copy_frame,
            _library: library,
        })
    }

    pub fn ask(&mut self, value: Value) -> Result<Value, String> {
        let command = CString::new(value.to_string()).map_err(error)?;
        // SAFETY: this owner retains the handle, library and command throughout the call.
        let result = unsafe { (self.command)(self.handle, command.as_ptr()) };
        if result.is_null() {
            return Err("native media returned no result".into());
        }
        // SAFETY: ABI result is a NUL-terminated allocation retained until free below.
        let value = serde_json::from_slice::<Value>(unsafe { CStr::from_ptr(result) }.to_bytes());
        // SAFETY: return the allocation to its library once, including when parsing fails.
        unsafe { (self.free)(result) };
        let value = value.map_err(error)?;
        if let Some(error) = value["error"].as_str() {
            return Err(error.into());
        }
        Ok(value)
    }

    pub fn receive(&self, packet: &[u8]) -> bool {
        if !(7..=MAX_PACKET).contains(&packet.len()) {
            return false;
        }
        // SAFETY: retain both handle and readable packet until return.
        unsafe { (self.receive)(self.handle, packet.as_ptr(), packet.len()) == 1 }
    }

    pub fn packet(&mut self, buffer: &mut [u8; MAX_PACKET]) -> Option<usize> {
        // SAFETY: owner retains handle/library and exclusive writable output.
        let length = unsafe { (self.copy_packet)(self.handle, buffer.as_mut_ptr(), buffer.len()) };
        (length > 0 && length as usize <= buffer.len()).then_some(length as usize)
    }

    pub fn priority(&self, packet: &[u8]) -> bool {
        // SAFETY: retain handle/library and readable packet through the synchronous query.
        unsafe { (self.priority)(self.handle, packet.as_ptr(), packet.len()) == 1 }
    }

    pub fn push(&self, width: u32, height: u32, pixels: &[u8]) -> bool {
        // SAFETY: retain handle/library and a readable RGBA buffer until return.
        unsafe { (self.push)(self.handle, width, height, pixels.as_ptr(), pixels.len()) == 1 }
    }

    pub fn frame(&self, after: u64, pixels: &mut [u8]) -> Option<FrameInfo> {
        let mut info = FrameInfo::default();
        // SAFETY: retain handle/library and disjoint exclusively writable output allocations.
        let status = unsafe {
            (self.copy_frame)(
                self.handle,
                after,
                pixels.as_mut_ptr(),
                pixels.len(),
                &mut info,
            )
        };
        if status != 1
            || info.width == 0
            || info.height == 0
            || info.width > 1920
            || info.height > 1920
            || info.rgba_bytes as usize > pixels.len()
            || info.rgba_bytes as usize > MAX_RGBA
            || info.width as u64 * info.height as u64 * 4 != u64::from(info.rgba_bytes)
        {
            return None;
        }
        Some(info)
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        // SAFETY: owner returns the unique handle before unloading its library.
        unsafe { (self.drop_engine)(self.handle) };
    }
}

fn library_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "mosh_native_media.dll"
    } else if cfg!(target_os = "macos") {
        "libmosh_native_media.dylib"
    } else {
        "libmosh_native_media.so"
    }
}

pub(crate) fn artifact(variable: &str, name: &str) -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os(variable) {
        return Ok(PathBuf::from(path));
    }
    let executable = std::env::current_exe().map_err(error)?;
    let directory = executable.parent().ok_or("missing executable directory")?;
    for path in [
        directory.join(name),
        directory.join("lib").join(name),
        directory.join("../Frameworks").join(name),
        directory.join("../Helpers").join(name),
    ] {
        if path.is_file() {
            return Ok(path);
        }
    }
    Err(format!("packaged native artifact is missing: {name}"))
}

fn error(error: impl std::fmt::Display) -> String {
    error.to_string()
}
