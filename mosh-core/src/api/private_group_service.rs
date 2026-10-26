//! Group maintenance shares the serialized native service lifecycle.
use super::*;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use std::time::Duration;

pub(super) fn start() -> Result<(), String> {
    RUNTIME.start_service(Duration::from_millis(500), |runtime| {
        if let Err(error) = runtime.service() {
            dlog::write(LogLevel::Warn, kinds::SERVICE, "group", &error.to_string());
        }
    })
}
