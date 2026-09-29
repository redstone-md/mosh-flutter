use std::io::{self, BufRead, Write};

// A pipe fixture for NativePeer's reply reader, independent of the Moss protocol.
fn main() {
    // Like the real worker, host the Go runtime that inspects inherited stdio.
    start_moss_runtime();
    let marker = std::path::PathBuf::from(std::env::var("MOSH_LINK_TEST_DIR").unwrap())
        .join("stdout-drained");
    for command in io::stdin().lock().lines() {
        let command = command.unwrap();
        if command.contains("\"shutdown\"")
            || std::env::var("MOSH_LINK_TEST_API").as_deref() == Ok("1")
        {
            break;
        }
        if command.contains("\"prepare\"") {
            println!(
                "MOSH_TEST_JSON {{\"marker\":{:?}}}",
                marker.to_string_lossy()
            );
            io::stdout().flush().unwrap();
            io::stdout().write_all(&vec![b'x'; 1024 * 1024]).unwrap();
            io::stdout().write_all(b"\n").unwrap();
            io::stdout().flush().unwrap();
            std::fs::write(&marker, b"drained").unwrap();
        } else {
            println!("MOSH_TEST_JSON {{\"phase\":\"Idle\"}}");
            io::stdout().flush().unwrap();
        }
    }
}

/// Load the prepared Moss library and wait for Go's package initialization.
#[cfg(windows)]
fn start_moss_runtime() {
    use std::ffi::{c_char, c_void};
    #[link(name = "kernel32")]
    extern "system" {
        fn LoadLibraryA(name: *const u8) -> *mut c_void;
        fn GetProcAddress(module: *mut c_void, name: *const u8) -> *mut c_void;
    }
    unsafe {
        let module = LoadLibraryA(b"moss-runtime\\moss.dll\0".as_ptr());
        assert!(!module.is_null(), "prepared Moss library must load");
        let version = GetProcAddress(module, b"Moss_Version\0".as_ptr());
        assert!(!version.is_null(), "Moss_Version must be exported");
        // Exported Go calls wait until the runtime, including `os`, is initialized.
        let version: extern "C" fn() -> *mut c_char = std::mem::transmute(version);
        version();
    }
}

// Go leaves synchronous Unix descriptors untouched; only Windows handles are affected.
#[cfg(not(windows))]
fn start_moss_runtime() {}
