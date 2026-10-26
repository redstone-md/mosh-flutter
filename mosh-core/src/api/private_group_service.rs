//! The existing private-group owner continues protocol work without a UI poller.
use super::*;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use std::time::Duration;

pub(super) fn start() -> Result<(), String> {
    std::thread::Builder::new()
        .name("mosh-group-service".into())
        .spawn(|| loop {
            std::thread::sleep(Duration::from_millis(500));
            if !turn() {
                return;
            }
            // Reconciliation may inspect other owners. The turn released the
            // group mutex and passive execution lease before this call.
            super::super::background::reconcile();
        })
        .map(drop)
        .map_err(|error| format!("could not start group service: {error}"))
}

fn turn() -> bool {
    let Some(mutex) = RUNTIME.initialized() else {
        return true;
    };
    let Ok(_authority) = super::super::background::execution_lease() else {
        return false;
    };
    if !super::super::background::network_permitted() {
        return true;
    }
    let Ok(mut runtime) = mutex.lock() else {
        return false;
    };
    if let Err(error) = runtime.service() {
        dlog::write(LogLevel::Warn, kinds::SERVICE, "group", &error.to_string());
    }
    true
}
