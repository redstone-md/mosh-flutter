//! The macOS home of the history key (DEK): a 0600 file next to the database,
//! inside the app's sandbox container.
//!
//! Why not the keychain: without an Apple Team ID the keychain ties an item
//! to the exact build that wrote it (a `cdhash:` partition). Every update is a
//! new build, so macOS asked for the login password again — twice — and
//! "Always Allow" only ever covered the build that was already gone. A
//! self-signed certificate does not change that; only a Developer ID does.
//!
//! What this gives up: the key is no longer wrapped by the login password.
//! At rest it is protected by FileVault, and on macOS 14+ other apps must ask
//! the user before they read another app's container. ADR 0011 records the
//! trade.
//!
//! Existing installs hand the key over once: the first read finds no file,
//! takes the key from the keychain (the last password prompt), writes the
//! file and then deletes the keychain item.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::secure_storage::{OsSecureSecretStore, SecureSecretStore, SecureStorageError};

const KEY_FILE_EXTENSION: &str = "key";
const TEMP_FILE_EXTENSION: &str = "key.tmp";
const LOG_CONTEXT: &str = "file-secret-store";

pub struct FileSecretStore {
    dir: PathBuf,
}

impl FileSecretStore {
    pub fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_path_buf(),
        }
    }

    fn path(&self, key: &str) -> PathBuf {
        self.dir.join(key).with_extension(KEY_FILE_EXTENSION)
    }

    /// Moves `key` out of the keychain into its file. The keychain item is
    /// deleted only after the file holds the same bytes, so a failed write
    /// never loses the key.
    fn hand_over_from_keychain(&self, key: &str) -> Result<Vec<u8>, SecureStorageError> {
        let keychain = OsSecureSecretStore;
        let secret = keychain.load_secret(key)?;
        self.save_secret(key, &secret)?;
        if self.read(key).ok().as_deref() == Some(secret.as_slice()) {
            let _ = keychain.delete_secret(key);
            dlog::write(
                LogLevel::Info,
                kinds::IDENTITY,
                LOG_CONTEXT,
                "history key moved from the keychain to the app container",
            );
        }
        Ok(secret)
    }

    fn read(&self, key: &str) -> std::io::Result<Vec<u8>> {
        fs::read(self.path(key))
    }
}

impl SecureSecretStore for FileSecretStore {
    fn load_secret(&self, key: &str) -> Result<Vec<u8>, SecureStorageError> {
        match self.read(key) {
            Ok(secret) => Ok(secret),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.hand_over_from_keychain(key)
            }
            Err(error) => Err(SecureStorageError::Backend(error.to_string())),
        }
    }

    /// Writes through a temp file and a rename, so a crash mid-write leaves
    /// the old key or the new one, never half of one.
    fn save_secret(&self, key: &str, value: &[u8]) -> Result<(), SecureStorageError> {
        let backend = |error: std::io::Error| SecureStorageError::Backend(error.to_string());
        fs::create_dir_all(&self.dir).map_err(backend)?;
        let temp = self.dir.join(key).with_extension(TEMP_FILE_EXTENSION);
        let mut file = owner_only_file(&temp).map_err(backend)?;
        file.write_all(value).map_err(backend)?;
        file.sync_all().map_err(backend)?;
        fs::rename(&temp, self.path(key)).map_err(backend)
    }

    fn delete_secret(&self, key: &str) -> Result<(), SecureStorageError> {
        fs::remove_file(self.path(key))
            .map_err(|error| SecureStorageError::Backend(error.to_string()))
    }
}

#[cfg(unix)]
fn owner_only_file(path: &Path) -> std::io::Result<fs::File> {
    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
}

#[cfg(not(unix))]
fn owner_only_file(path: &Path) -> std::io::Result<fs::File> {
    fs::File::create(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mosh-file-secret-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn roundtrip_keeps_the_bytes() {
        let dir = temp_dir("roundtrip");
        let store = FileSecretStore::new(&dir);
        let secret = [0u8, 1, 2, 255];

        store.save_secret("k", &secret).expect("save");
        assert_eq!(store.load_secret("k").expect("load"), secret);

        store.delete_secret("k").expect("delete");
        let _ = fs::remove_dir_all(&dir);
    }

    /// An install that kept its key in the keychain must keep its history:
    /// the key moves into the file and leaves the keychain.
    #[test]
    fn a_keychain_key_is_handed_over_once() {
        const KEY: &str = "file-secret-store-handover-test";
        let dir = temp_dir("handover");
        let keychain = OsSecureSecretStore;
        let secret = [9u8, 8, 7, 6];
        keychain.save_secret(KEY, &secret).expect("seed keychain");

        let store = FileSecretStore::new(&dir);
        assert_eq!(store.load_secret(KEY).expect("handover"), secret);

        assert_eq!(store.read(KEY).expect("file written"), secret);
        assert!(
            keychain.load_secret(KEY).is_err(),
            "the keychain item must be gone after the handover"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn the_key_file_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let dir = temp_dir("mode");
        let store = FileSecretStore::new(&dir);
        store.save_secret("k", b"x").expect("save");

        let mode = fs::metadata(store.path("k"))
            .expect("meta")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        let _ = fs::remove_dir_all(&dir);
    }
}
