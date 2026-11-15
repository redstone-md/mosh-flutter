//! iOS has no JVM to call into: the runner registers one C function at
//! launch (`mosh_ios_media_register`) that takes a JSON command and returns
//! its JSON answer allocated with `malloc`, which this side frees.
use serde_json::Value;
use std::{
    ffi::{c_char, c_void, CStr, CString},
    sync::OnceLock,
};

type Command = unsafe extern "C" fn(*const c_char) -> *mut c_char;
static COMMAND: OnceLock<Command> = OnceLock::new();

unsafe extern "C" {
    fn free(pointer: *mut c_void);
}

/// Called once by `CallMedia.swift` before Flutter starts.
#[no_mangle]
pub extern "C" fn mosh_ios_media_register(command: Command) {
    let _ = COMMAND.set(command);
}

pub(crate) fn command(value: Value) -> Result<Value, String> {
    let command = COMMAND.get().ok_or("iOS media adapter is missing")?;
    let json = CString::new(value.to_string()).map_err(|error| error.to_string())?;
    // SAFETY: the runner's function reads the NUL-terminated command during
    // the call and returns a NUL-terminated `malloc` allocation or null.
    let response = unsafe { command(json.as_ptr()) };
    if response.is_null() {
        return Err("iOS media adapter returned nothing".into());
    }
    // SAFETY: non-null, NUL-terminated and owned by this side from here.
    let text = unsafe { CStr::from_ptr(response) }
        .to_string_lossy()
        .into_owned();
    // SAFETY: freed once, with the allocator that made it.
    unsafe { free(response.cast()) };
    super::reply(&text)
}
