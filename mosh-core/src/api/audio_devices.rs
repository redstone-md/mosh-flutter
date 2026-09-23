//! Audio-device picks facade: enumerate cpal output devices and persist
//! the input/output picks the settings screen edits.
//!
//! The input pick is NOT resolved here — Dart hands it to `record`'s
//! `RecordConfig.device` (the `record` plugin owns input enumeration on
//! every platform we ship). The output pick IS resolved here, at stream
//! start, because playback and the ringtone live in cpal inside this
//! crate: `resolve_output_device` maps the stored id to a cpal `Device`,
//! falling back to the default device on ANY failure (garbage string,
//! unplugged device) so a stale pick can never break a call or a ringtone.
//!
//! Bridge-friendliness: plain `Option<String>` for the picks, a list of
//! `AudioDeviceInfo {id, name}` for enumeration, `Result<_, String>`
//! matching the voice-call facades' error style.

use cpal::default_host;
use cpal::traits::{DeviceTrait, HostTrait};
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use crate::api::shared_runtime::resolved_data_dir;
use crate::audio_devices::{self, AudioDevicesSetting};

/// One enumerable output device: the cpal `DeviceId` stringified (the
/// stable persisted form, `host:device`) plus the human label for the
/// dropdown.
#[frb]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDeviceInfo {
    /// `DeviceId::to_string()` — the value to store as the output pick.
    pub id: String,
    /// The device label (`Device: Display`, e.g. "Built-in Speakers").
    pub name: String,
}

/// Lists every output device cpal can see on the default host. Devices
/// that fail to describe themselves are skipped, not fatal: a dropdown
/// with two working entries beats an error over one broken one.
#[frb(sync)]
pub fn list_output_devices() -> Vec<AudioDeviceInfo> {
    let host = default_host();
    let Ok(outputs) = host.output_devices() else {
        return Vec::new();
    };
    outputs
        .filter_map(|device| {
            let id = device.id().ok()?.to_string();
            Some(AudioDeviceInfo {
                id,
                name: device.to_string(),
            })
        })
        .collect()
}

/// The stored input device pick, or `None` for the system default.
#[frb(sync)]
pub fn audio_input_device_id() -> Option<String> {
    audio_devices::load(&resolved_data_dir()).input_device_id
}

/// The stored output device pick, or `None` for the system default.
#[frb(sync)]
pub fn audio_output_device_id() -> Option<String> {
    audio_devices::load(&resolved_data_dir()).output_device_id
}

/// Persists BOTH picks in one write: the settings screen edits them as a
/// pair, and a partial update losing the other field would surprise the
/// user. `None` clears the pick back to the system default.
#[frb(sync)]
pub fn set_audio_devices(
    input_device_id: Option<String>,
    output_device_id: Option<String>,
) -> Result<(), String> {
    audio_devices::save(
        &resolved_data_dir(),
        &AudioDevicesSetting {
            input_device_id,
            output_device_id,
        },
    )
    .map_err(|error| format!("audio-devices save: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enumeration_never_panics_and_ids_are_nonempty() {
        // Smoke: enumeration is safe on any host shape (empty list is fine).
        let devices = list_output_devices();
        for device in &devices {
            assert!(!device.id.is_empty());
            assert!(!device.name.is_empty());
        }
    }
}
