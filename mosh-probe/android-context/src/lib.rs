//! Exercise the production JNI bootstrap using a real host JVM.
#[path = "../../../mosh-core/src/android.rs"]
mod android;

#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshNative_contextReady(
    _env: jni::EnvUnowned<'_>,
    _class: jni::objects::JClass<'_>,
) -> jni::sys::jboolean {
    std::panic::catch_unwind(ndk_context::android_context).is_ok()
}
