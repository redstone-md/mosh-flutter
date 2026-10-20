//! Camera adapters publish one latest, owned RGBA frame to the call owner.
use std::time::Instant;
#[cfg(not(target_os = "android"))]
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(target_os = "android")]
#[path = "capture/android.rs"]
mod platform;
#[cfg(not(target_os = "android"))]
#[path = "capture/desktop.rs"]
mod platform;
pub(crate) use platform::{Capture, Query};

pub(crate) struct Captured {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub received: Instant,
    pub source_age_ms: u32,
}

#[cfg(not(target_os = "android"))]
pub(crate) fn wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
