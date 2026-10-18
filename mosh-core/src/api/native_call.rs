//! Desktop call controls and presentation; no media keys cross this bridge.
pub use crate::native_call::types::{Device, Frame, Snapshot};
use crate::native_call::{types::Choices, Hub};
use flutter_rust_bridge::frb;
use std::sync::{Arc, OnceLock};

static HUB: OnceLock<Arc<Hub>> = OnceLock::new();

/// Inventory only: does not prepare a call or open a capture stream.
pub fn list_cameras() -> Result<Vec<Device>, String> {
    crate::native_call::list_cameras()
}

#[frb(sync)]
pub fn default_camera_id() -> Option<String> {
    crate::audio_devices::load(&super::shared_runtime::resolved_data_dir()).camera_device_id
}

#[frb(sync)]
pub fn set_default_camera(camera_id: Option<String>) -> Result<(), String> {
    let directory = super::shared_runtime::resolved_data_dir();
    let mut settings = crate::audio_devices::load(&directory);
    settings.camera_device_id = camera_id;
    crate::audio_devices::save(&directory, &settings)
        .map_err(|error| format!("camera preference save: {error}"))
}

pub fn prepare(
    session_id: String,
    call_id: String,
    microphone: bool,
    camera: bool,
) -> Result<(), String> {
    let settings = crate::audio_devices::load(&super::shared_runtime::resolved_data_dir());
    let camera_id = settings.camera_device_id.filter(|id| {
        list_cameras()
            .unwrap_or_default()
            .iter()
            .any(|device| device.stable && device.id == *id)
    });
    let choices = Choices {
        microphone,
        microphone_allowed: false,
        camera,
        input: settings.input_device_id,
        output: settings.output_device_id,
        camera_id,
    };
    let hub = super::private_dm::ensure_runtime()
        .map_err(|error| error.to_string())?
        .prepare_native_call(&session_id, &call_id, choices)?;
    HUB.get_or_init(|| hub);
    Ok(())
}

// Bridge fields stay explicit; the native owner receives one Choices value.
#[allow(clippy::too_many_arguments)]
pub fn set_choices(
    session_id: String,
    call_id: String,
    microphone: bool,
    microphone_allowed: bool,
    camera: bool,
    input: Option<String>,
    output: Option<String>,
    camera_id: Option<String>,
) -> Result<(), String> {
    hub()?.choices(
        &session_id,
        &call_id,
        Choices {
            microphone,
            microphone_allowed,
            camera,
            input,
            output,
            camera_id,
        },
    )
}

pub fn snapshot(session_id: String, call_id: String) -> Result<Option<Snapshot>, String> {
    Ok(hub()?.snapshot(&session_id, &call_id))
}

pub fn frame(
    session_id: String,
    call_id: String,
    local: bool,
    after: u64,
) -> Result<Option<Frame>, String> {
    Ok(hub()?.frame(&session_id, &call_id, local, after))
}

fn hub() -> Result<&'static Arc<Hub>, String> {
    HUB.get()
        .ok_or_else(|| "native call is not prepared".into())
}
