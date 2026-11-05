//! Android loads this library through `System.loadLibrary`, so libwebrtc's
//! JNI code captures the application class loader here. Kotlin then hands
//! the application context to `livekit.org.webrtc.ContextUtils`; mosh-core
//! opens the same, already loaded library afterwards.
use jni::{
    JavaVM,
    sys::{JNI_VERSION_1_6, jint},
};
use std::ffi::c_void;

/// # Safety
/// Called once by the Android runtime with its live VM.
#[unsafe(no_mangle)]
pub unsafe extern "system" fn JNI_OnLoad(vm: *mut jni::sys::JavaVM, _: *mut c_void) -> jint {
    // SAFETY: the runtime passes a valid VM pointer that outlives the process.
    if let Ok(vm) = unsafe { JavaVM::from_raw(vm) } {
        libwebrtc::android::initialize_android(&vm);
    }
    JNI_VERSION_1_6
}
