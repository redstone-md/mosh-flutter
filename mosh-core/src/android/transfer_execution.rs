//! Synchronous OS start/stop fence. This performs no persistence or network I/O.
use jni::{
    errors::{Error, ThrowRuntimeExAndDefault},
    objects::{JClass, JString},
    EnvUnowned,
};

#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshNative_setTransferExecution<'caller>(
    mut unowned: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    incarnation: JString<'caller>,
    id: JString<'caller>,
    generation: i64,
    allowed: u8,
) -> i32 {
    unowned
        .with_env(|env| -> Result<i32, Error> {
            let incarnation = incarnation.mutf8_chars(env)?.to_str().into_owned();
            let id = id.mutf8_chars(env)?.to_str().into_owned();
            Ok(crate::api::background::transfer_grants::set(
                &incarnation,
                &id,
                generation,
                allowed != 0,
            ))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// Actual Activity/access state, synchronously revoked before Dart sees a hint.
#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshNative_setTransferInteractive(
    _env: EnvUnowned<'_>,
    _class: JClass<'_>,
    interactive: u8,
) -> i32 {
    crate::api::background::transfer_grants::set_interactive(interactive != 0)
}
