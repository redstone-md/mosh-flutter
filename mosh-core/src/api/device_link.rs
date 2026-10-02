//! Thin desktop device-link facade, ADR 0029. Uses the shared node and store.
use std::sync::{Mutex, MutexGuard, OnceLock};
use std::time::Duration;

pub use crate::device_link::types::{DeviceLinkError, DeviceLinkErrorKind, DeviceLinkSnapshot};
use crate::device_link::DeviceLinkRuntime;

static RUNTIME: OnceLock<Mutex<Result<DeviceLinkRuntime, DeviceLinkError>>> = OnceLock::new();

fn runtime(
) -> Result<MutexGuard<'static, Result<DeviceLinkRuntime, DeviceLinkError>>, DeviceLinkError> {
    let cell = RUNTIME.get_or_init(|| {
        let result = construct();
        if result.is_ok() {
            std::thread::spawn(|| loop {
                std::thread::sleep(Duration::from_millis(500));
                let Some(cell) = RUNTIME.get() else { continue };
                if let Ok(mut guard) = cell.lock() {
                    if let Ok(rt) = guard.as_mut() {
                        let _ = rt.service();
                    }
                }
            });
        }
        Mutex::new(result)
    });
    cell.lock()
        .map_err(|_| DeviceLinkError::new(DeviceLinkErrorKind::Unavailable))
}

fn construct() -> Result<DeviceLinkRuntime, DeviceLinkError> {
    let resources = crate::api::shared_runtime::ensure_shared_resources()
        .map_err(|_| DeviceLinkError::new(DeviceLinkErrorKind::Unavailable))?;
    let persistence = resources
        .persistence
        .ok_or_else(|| DeviceLinkError::new(DeviceLinkErrorKind::Storage))?;
    DeviceLinkRuntime::open(resources.shared_node, persistence)
}

fn with_runtime(
    action: impl FnOnce(&mut DeviceLinkRuntime) -> Result<DeviceLinkSnapshot, DeviceLinkError>,
) -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    let mut guard = runtime()?;
    match guard.as_mut() {
        Ok(rt) => action(rt),
        Err(error) => Err(error.clone()),
    }
}

pub fn snapshot() -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(DeviceLinkRuntime::snapshot)
}

pub fn begin_link() -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(DeviceLinkRuntime::begin_link)
}

pub fn join_link(uri: String, device_name: String) -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(|rt| rt.join_link(uri, device_name))
}

pub fn approve(confirmation_code: String) -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(|rt| rt.approve(confirmation_code))
}

pub fn cancel() -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(DeviceLinkRuntime::cancel)
}

pub fn revoke(device_id: String) -> Result<DeviceLinkSnapshot, DeviceLinkError> {
    with_runtime(|rt| rt.revoke(device_id))
}
