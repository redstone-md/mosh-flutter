//! JNI calls use a retained application-loader class, including on native threads.
use jni::{
    errors::{Error, ThrowRuntimeExAndDefault},
    objects::{JClass, JString, JValue},
    refs::Global,
    EnvUnowned,
};
use serde_json::Value;
use std::sync::OnceLock;

static CLASS: OnceLock<Global<JClass<'static>>> = OnceLock::new();

#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshMedia_register<'caller>(
    mut env: EnvUnowned<'caller>,
    class: JClass<'caller>,
) {
    env.with_env(|env| -> Result<(), Error> {
        let _ = CLASS.set(env.new_global_ref(class)?);
        Ok(())
    })
    .resolve::<ThrowRuntimeExAndDefault>();
}

/// The JSON boundary carries device metadata/commands, never media pixels.
pub(crate) fn command(value: Value) -> Result<Value, String> {
    let app = super::APPLICATION
        .get()
        .ok_or("Android context is missing")?;
    let class = CLASS.get().ok_or("Android media adapter is missing")?;
    let response = app
        ._vm
        .attach_current_thread(|env| -> Result<String, Error> {
            let json = env.new_string(value.to_string())?;
            let result = env
                .call_static_method(
                    class,
                    jni::jni_str!("command"),
                    jni::jni_sig!("(Ljava/lang/String;)Ljava/lang/String;"),
                    &[JValue::Object(json.as_ref())],
                )?
                .l()?;
            let text = JString::cast_local(env, result)?;
            let response = text.mutf8_chars(env)?.to_str().into_owned();
            Ok(response)
        })
        .map_err(|error| format!("Android media command: {error}"))?;
    let result: Value = serde_json::from_str(&response).map_err(|error| error.to_string())?;
    if let Some(error) = result["error"].as_str() {
        return Err(error.into());
    }
    Ok(result)
}
