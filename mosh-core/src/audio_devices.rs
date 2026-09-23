//! The audio-devices setting: which input (mic) and output (speaker)
//! device the voice paths should use. One app-level answer, deliberately a
//! plain JSON file in the data dir like the read-receipts toggle: not a
//! secret, and readable on a launch where the encrypted store is slow.
//!
//! `None` means "system default" — the unset state and the explicit
//! reset are the same thing, so only a real pick persists. Unknown ids
//! (a device unplugged between runs) are tolerated by the CALLERS, not
//! here: a stale id is a valid stored answer whose resolution at use time
//! falls back to the default device.

use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;

use cpal::traits::HostTrait;
use cpal::{default_host, Device, DeviceId, Host};
use serde::{Deserialize, Serialize};

const FILE_NAME: &str = "audio-devices.json";

/// The stored answer: device ids as the platform reports them
/// (`record`'s `InputDevice.id` for input, cpal's `DeviceId.to_string()`
/// for output). Both optional: only an explicit pick persists.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioDevicesSetting {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_device_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_device_id: Option<String>,
}

pub fn setting_path(config_dir: &Path) -> PathBuf {
    config_dir.join(FILE_NAME)
}

/// Reads the stored picks. Absent, unreadable and malformed all mean
/// "system default" rather than a failed launch over a config file.
pub fn load(config_dir: &Path) -> AudioDevicesSetting {
    let raw = match fs::read(setting_path(config_dir)) {
        Ok(raw) => raw,
        Err(_) => return AudioDevicesSetting::default(),
    };
    serde_json::from_slice(&raw).unwrap_or_default()
}

/// Writes the picks down. `None` fields do not persist as keys, so a
/// reset-to-default shrinks the file rather than storing a stale null.
pub fn save(config_dir: &Path, setting: &AudioDevicesSetting) -> std::io::Result<()> {
    fs::create_dir_all(config_dir)?;
    let body = serde_json::to_vec_pretty(setting)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    fs::write(setting_path(config_dir), body)
}

/// Resolves the stored output pick to a cpal device for a stream start
/// (playback, ringtone). Order: an explicit pick that matches a live
/// device wins; a pick that fails to parse or no longer exists logs and
/// falls back to the default device; `None` (or an empty string) goes
/// straight to the default. The fallback is the designed behavior, not an
/// error — a device unplugged between runs must never break a call or a
/// ringtone.
///
/// Lives HERE, not in `api::audio_devices`: the frb scanner mirrors every
/// public fn in an `api::` module, and a cpal `Device` is not a
/// bridgeable type. The two stream starts in `api::voice_call_*` call it
/// directly.
pub fn resolve_output_device(stored_id: Option<&str>) -> Result<Device, String> {
    let host = default_host();
    let Some(raw) = stored_id.filter(|id| !id.is_empty()) else {
        return default_output(&host);
    };
    match DeviceId::from_str(raw) {
        Ok(id) => {
            if let Some(device) = host.device_by_id(&id) {
                return Ok(device);
            }
            log_fallback(&format!(
                "stored output device not found ({raw}); using default"
            ));
        }
        Err(error) => {
            log_fallback(&format!(
                "stored output device id unreadable ({raw}: {error}); using default"
            ));
        }
    }
    default_output(&host)
}

fn default_output(host: &Host) -> Result<Device, String> {
    host.default_output_device()
        .ok_or_else(|| "cpal: no default output device".to_string())
}

fn log_fallback(message: &str) {
    crate::diagnostics_log::write(
        crate::diagnostics_log::LogLevel::Warn,
        crate::diagnostics_log::kinds::VOICE,
        "audio-devices",
        message,
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mosh-audio-devices-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    // The resolver's contract on this host: None (and "") must resolve to
    // SOME device when the host has any output at all — CI runners and dev
    // boxes both do. A garbage id must resolve too (the fallback path),
    // never error: a stale pick degrades to the default device.
    #[test]
    fn fallback_paths_resolve_when_the_host_has_an_output() {
        if default_host().default_output_device().is_none() {
            // Headless CI box: the contract is untestable here, not broken.
            return;
        }
        assert!(
            resolve_output_device(None).is_ok(),
            "no pick resolves to the default device"
        );
        assert!(
            resolve_output_device(Some("")).is_ok(),
            "an empty pick is the default, not a parse error"
        );
        assert!(
            resolve_output_device(Some("host-that-does-not-exist:device")).is_ok(),
            "a garbage pick degrades to the default device, never errors"
        );
        assert!(
            resolve_output_device(Some("coreaudio:gone")).is_ok(),
            "an unresolvable pick degrades to the default device"
        );
    }

    #[test]
    fn picks_round_trip_and_reset_shrinks_the_file() {
        let dir = scratch("roundtrip");
        assert_eq!(
            load(&dir),
            AudioDevicesSetting::default(),
            "nothing stored yet — system defaults"
        );

        save(
            &dir,
            &AudioDevicesSetting {
                input_device_id: Some("avcapture:Built-in Microphone".to_string()),
                output_device_id: Some("coreaudio:AppleHDAEngineOutput".to_string()),
            },
        )
        .expect("picks should save");
        let stored = load(&dir);
        assert_eq!(
            stored.input_device_id.as_deref(),
            Some("avcapture:Built-in Microphone")
        );
        assert_eq!(
            stored.output_device_id.as_deref(),
            Some("coreaudio:AppleHDAEngineOutput")
        );

        // Reset to default: only the input stays, the output key vanishes.
        save(
            &dir,
            &AudioDevicesSetting {
                input_device_id: Some("avcapture:Built-in Microphone".to_string()),
                output_device_id: None,
            },
        )
        .expect("reset should save");
        let stored = load(&dir);
        assert_eq!(stored.output_device_id, None, "a reset is the default");
        assert!(stored.input_device_id.is_some(), "the other pick survives");
        let raw = fs::read_to_string(setting_path(&dir)).expect("file readable");
        assert!(
            !raw.contains("output_device_id"),
            "a reset pick must not persist as a null key"
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn broken_or_missing_file_reads_as_defaults() {
        let dir = scratch("broken");
        fs::create_dir_all(&dir).expect("scratch dir should exist");
        fs::write(setting_path(&dir), b"{not json").expect("broken file should write");
        assert_eq!(
            load(&dir),
            AudioDevicesSetting::default(),
            "a malformed file is the default, not an error"
        );
        assert_eq!(
            load(&dir.join("missing")),
            AudioDevicesSetting::default(),
            "a missing dir is the default"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    // A stale pick (device unplugged) is a VALID stored answer; the
    // resolver at use time owns the fallback, so the store must hand it
    // through untouched.
    #[test]
    fn a_stale_pick_is_returned_untouched() {
        let dir = scratch("stale");
        save(
            &dir,
            &AudioDevicesSetting {
                input_device_id: None,
                output_device_id: Some("coreaudio:gone-device".to_string()),
            },
        )
        .expect("stale pick should save");
        assert_eq!(
            load(&dir).output_device_id.as_deref(),
            Some("coreaudio:gone-device"),
            "the store does not validate picks — resolution at use time does"
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
