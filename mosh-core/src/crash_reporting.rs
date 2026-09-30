//! The crash-reporting consent (ADR 0035): opt-in, off by default.
//!
//! A plain JSON file in the data dir, like the read-receipts toggle: the
//! answer is not a secret and must be readable before the encrypted store
//! opens, because the reporter starts early in launch.
//!
//! The file holds the install's scrub salt, and its presence is the consent.
//! Dart hashes identifiers in outgoing reports with this salt, so reports
//! from one install correlate with each other but never with the real ids.
//! Turning reporting off deletes the file, so the salt goes with it: a later
//! opt-in starts as a new, unlinkable install.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rand::RngCore;
use serde::{Deserialize, Serialize};

const FILE_NAME: &str = "crash-reporting.json";
/// Salt length in bytes before hex encoding.
const SALT_BYTES: usize = 16;

/// Serializes enable/disable, so two concurrent enables cannot mint two
/// salts. In-process only: one app instance owns the data dir.
static CONSENT_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct CrashReportingConsent {
    salt: String,
}

pub fn consent_path(config_dir: &Path) -> PathBuf {
    config_dir.join(FILE_NAME)
}

/// The salt when the user opted in; `None` otherwise. Absent, unreadable
/// and malformed all read as "off", the default.
pub fn salt(config_dir: &Path) -> Option<String> {
    let raw = fs::read(consent_path(config_dir)).ok()?;
    let consent: CrashReportingConsent = serde_json::from_slice(&raw).ok()?;
    (!consent.salt.is_empty()).then_some(consent.salt)
}

/// Opts in and returns the salt. Keeps an existing salt, so enabling twice
/// does not split one install into two.
pub fn enable(config_dir: &Path) -> std::io::Result<String> {
    let _guard = CONSENT_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(existing) = salt(config_dir) {
        return Ok(existing);
    }
    let mut bytes = [0u8; SALT_BYTES];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let consent = CrashReportingConsent {
        salt: hex::encode(bytes),
    };
    fs::create_dir_all(config_dir)?;
    let body = serde_json::to_vec_pretty(&consent)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    fs::write(consent_path(config_dir), body)?;
    Ok(consent.salt)
}

/// Opts out: deletes the file, and with it the salt. Already-off is fine.
pub fn disable(config_dir: &Path) -> std::io::Result<()> {
    let _guard = CONSENT_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    match fs::remove_file(consent_path(config_dir)) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "mosh-crash-reporting-{}-{name}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn enable_is_stable_and_disable_forgets_the_salt() {
        let dir = scratch("cycle");
        assert_eq!(salt(&dir), None, "off by default");

        let first = enable(&dir).expect("enable should save");
        assert_eq!(first.len(), SALT_BYTES * 2);
        assert_eq!(enable(&dir).expect("re-enable"), first, "same install");
        assert_eq!(salt(&dir), Some(first.clone()));

        disable(&dir).expect("disable should delete");
        assert_eq!(salt(&dir), None);
        disable(&dir).expect("disabling twice is fine");

        let second = enable(&dir).expect("enable again");
        assert_ne!(second, first, "a new opt-in is a new, unlinkable install");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn malformed_file_reads_as_off() {
        let dir = scratch("broken");
        fs::create_dir_all(&dir).expect("scratch dir");
        fs::write(consent_path(&dir), b"{not json").expect("write");
        assert_eq!(salt(&dir), None);
        fs::write(consent_path(&dir), br#"{"salt":""}"#).expect("write");
        assert_eq!(salt(&dir), None, "an empty salt is no consent");
        let _ = fs::remove_dir_all(&dir);
    }
}
