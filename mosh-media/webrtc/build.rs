//! On Android, LiveKit's libwebrtc.jar reaches libwebrtc through JNI entry
//! points (`Java_livekit_org_webrtc_*`) in the static libwebrtc.a. Nothing in
//! Rust references them, so the linker drops them unless this library keeps
//! and exports them, as LiveKit's own FFI crate does. webrtc-sys asks for the
//! same, but Cargo does not pass a dependency's link arguments on to a cdylib.
fn main() {
    println!("cargo:rerun-if-env-changed=LK_CUSTOM_WEBRTC");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        webrtc_sys_build::configure_jni_symbols().expect("libwebrtc JNI symbols");
    }
}
