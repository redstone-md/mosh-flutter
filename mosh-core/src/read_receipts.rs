//! The read-receipts toggle: one app-level answer covering every DM.
//!
//! Deliberately a plain JSON file in the data dir, like the VPN consent:
//! the answer is not a secret, and it has to be readable on a launch where
//! the encrypted store is slow to open.
//!
//! Unlike the consent, BOTH answers persist. The feature defaults to off,
//! so an absent file means "never answered" and stays off; but a user who
//! switched it on must stay on across launches, and a user who switched it
//! off must stay off — the file stores the actual boolean either way.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const FILE_NAME: &str = "read-receipts.json";

/// The stored answer: whether this device sends read receipts (and, by the
/// symmetry rule, shows the ones it receives).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadReceiptsSetting {
    pub enabled: bool,
}

pub fn setting_path(config_dir: &Path) -> PathBuf {
    config_dir.join(FILE_NAME)
}

/// Reads a stored answer. Absent, unreadable and malformed all mean the
/// same thing — the feature is off, its default — rather than the launch
/// failing over a config file.
pub fn load(config_dir: &Path) -> Option<ReadReceiptsSetting> {
    let raw = fs::read(setting_path(config_dir)).ok()?;
    serde_json::from_slice(&raw).ok()
}

/// Writes the answer down. Both values persist: an off is a decision too.
pub fn save(config_dir: &Path, setting: &ReadReceiptsSetting) -> std::io::Result<()> {
    fs::create_dir_all(config_dir)?;
    let body = serde_json::to_vec_pretty(setting)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    fs::write(setting_path(config_dir), body)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mosh-read-receipts-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    // Unlike the VPN consent (which stores only "yes"), an OFF must persist
    // too: the default is off, and the user's explicit off is a decision.
    #[test]
    fn both_answers_round_trip() {
        let dir = scratch("roundtrip");
        assert_eq!(load(&dir), None, "nothing stored yet — default off");

        save(&dir, &ReadReceiptsSetting { enabled: true }).expect("on should save");
        assert_eq!(
            load(&dir),
            Some(ReadReceiptsSetting { enabled: true }),
            "an explicit on persists"
        );

        save(&dir, &ReadReceiptsSetting { enabled: false }).expect("off should save");
        assert_eq!(
            load(&dir),
            Some(ReadReceiptsSetting { enabled: false }),
            "an explicit off persists too, it is not forgotten like a consent refusal"
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn broken_or_missing_file_reads_as_off() {
        let dir = scratch("broken");
        fs::create_dir_all(&dir).expect("scratch dir should exist");
        fs::write(setting_path(&dir), b"{not json").expect("broken file should write");
        assert_eq!(
            load(&dir),
            None,
            "a malformed file is the default, not an error"
        );
        assert_eq!(
            load(&dir.join("missing")),
            None,
            "a missing dir is the default"
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
