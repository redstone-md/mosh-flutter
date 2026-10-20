//! Android's JVM/application context outlives Activities and native audio threads.
use jni::{
    errors::{Error, ThrowRuntimeExAndDefault},
    objects::{JClass, JObject},
    refs::{Global, Reference},
    Env, EnvUnowned, JavaVM,
};
use std::sync::{Mutex, OnceLock};

struct Application {
    _vm: JavaVM,
    _context: Global<JObject<'static>>,
}

static APPLICATION: OnceLock<Application> = OnceLock::new();
static INITIALIZING: Mutex<()> = Mutex::new(());

fn initialize(env: &mut Env<'_>, application: JObject<'_>) -> Result<(), Error> {
    let _guard = INITIALIZING
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if APPLICATION.get().is_some() {
        return Ok(());
    }
    let vm = env.get_java_vm()?;
    let context = env.new_global_ref(application)?;
    if context.is_null() {
        return Err(Error::NullPtr("Android application context"));
    }
    // SAFETY: the VM and global application reference are retained for process
    // lifetime. The mutex and private OnceLock enforce exactly one initialization,
    // before Activity startup makes native audio reachable from Dart.
    unsafe {
        ndk_context::initialize_android_context(vm.get_raw().cast(), context.as_raw().cast());
    }
    let _ = APPLICATION.set(Application {
        _vm: vm,
        _context: context,
    });
    Ok(())
}

/// Called by MoshNative with Application context, never an Activity reference.
#[no_mangle]
pub extern "system" fn Java_app_mosh_mosh_MoshNative_initialize<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    application: JObject<'caller>,
) {
    unowned_env
        .with_env(|env| initialize(env, application))
        .resolve::<ThrowRuntimeExAndDefault>();
}
