//! Keep the worker's stdio usable after Moss starts its Go runtime.
//!
//! Dart gives child processes overlapped Windows pipes. Go's `os` package
//! adopts overlapped stdout/stderr and sets `FILE_SKIP_SET_EVENT_ON_HANDLE`,
//! while Rust std waits on that handle when a pipe write pends. The first
//! reply that does not fit the pipe then never returns. Workers therefore
//! move overlapped stdio to synchronous pipes, relayed to the inherited
//! handles by threads Go never sees. Synchronous stdio stays untouched.

/// Call before loading Moss. A no-op where stdio has no such conflict.
#[cfg(windows)]
pub fn isolate_from_moss() {
    use std::ffi::c_void;
    use std::fs::File;
    use std::os::windows::io::{AsRawHandle, FromRawHandle, IntoRawHandle, RawHandle};

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn SetStdHandle(id: u32, handle: *mut c_void) -> i32;
    }
    #[link(name = "ntdll")]
    unsafe extern "system" {
        fn NtQueryInformationFile(
            handle: RawHandle,
            status: *mut [usize; 2],
            info: *mut u32,
            length: u32,
            class: u32,
        ) -> i32;
    }
    // Go's `windows.IsNonblock`: no FILE_SYNCHRONOUS_IO_* mode bit is set.
    let overlapped = |handle: RawHandle| {
        const FILE_MODE_INFORMATION: u32 = 16;
        const SYNCHRONOUS_IO: u32 = 0x10 | 0x20;
        let (mut status, mut mode) = ([0; 2], 0);
        let queried = unsafe {
            NtQueryInformationFile(handle, &mut status, &mut mode, 4, FILE_MODE_INFORMATION)
        };
        queried == 0 && mode & SYNCHRONOUS_IO == 0
    };
    const STD_OUTPUT_HANDLE: u32 = -11i32 as u32;
    const STD_ERROR_HANDLE: u32 = -12i32 as u32;

    let inherited: [(u32, RawHandle); 2] = [
        (STD_OUTPUT_HANDLE, std::io::stdout().as_raw_handle()),
        (STD_ERROR_HANDLE, std::io::stderr().as_raw_handle()),
    ];
    for (id, handle) in inherited {
        if handle.is_null() || !overlapped(handle) {
            continue;
        }
        let (mut reader, writer) = std::io::pipe().expect("stdio relay pipe");
        // SAFETY: the process owns its standard handle for its whole lifetime.
        let mut target = unsafe { File::from_raw_handle(handle) };
        let replaced = unsafe { SetStdHandle(id, writer.into_raw_handle()) };
        assert_ne!(replaced, 0, "stdio relay must replace the standard handle");
        std::thread::spawn(move || std::io::copy(&mut reader, &mut target));
    }
}

#[cfg(not(windows))]
pub fn isolate_from_moss() {}
