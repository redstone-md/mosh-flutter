#[cfg(target_os = "macos")]
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use flutter_rust_bridge::frb;
use keyring_core::Entry;
#[cfg(not(target_os = "android"))]
use std::sync::OnceLock;

/// This app's keyring namespace. It is deliberately NOT the Tauri shell's
/// `app.mosh.desktop`: the two apps keep separate databases
/// (`app.mosh.desktop/mosh-history.redb` vs the Flutter
/// `app.mosh/mosh/mosh/history.redb`) but used to share one credential slot,
/// so whichever app rotated or deleted the DEK silently orphaned the other
/// one's history behind the fail-closed guard in `Persistence::open`.
const SERVICE_NAME: &str = "app.mosh.flutter";

/// The slot this app used to share with the Tauri shell. Reads fall back to
/// it once and migrate the secret forward, so an install that already holds a
/// working DEK there keeps its history instead of hitting the same
/// fail-closed error the rename was meant to prevent.
const LEGACY_SERVICE_NAME: &str = "app.mosh.desktop";
#[cfg(not(target_os = "android"))]
const BACKEND_NAME: &str = "os-keychain";
/// Android never resolves a DEK through this store: the app hands one in from
/// the Dart-side Keystore and `construct_resources` opens the database with
/// `open_with_dek`. Naming the backend keeps the diagnostics panel honest
/// rather than reporting a keychain that is not in the picture.
#[cfg(target_os = "android")]
const BACKEND_NAME: &str = "android-keystore (app-injected DEK)";
#[cfg(not(target_os = "android"))]
const NATIVE_STORE_ERROR: &str = "native secure store is unavailable";
#[cfg(target_os = "android")]
const NATIVE_STORE_ERROR: &str =
    "native secure store is not used on Android; the DEK is injected by the app";

pub trait SecureSecretStore {
    fn load_secret(&self, key: &str) -> Result<Vec<u8>, SecureStorageError>;
    fn save_secret(&self, key: &str, value: &[u8]) -> Result<(), SecureStorageError>;
    fn delete_secret(&self, key: &str) -> Result<(), SecureStorageError>;
}

#[derive(Debug, Clone, serde::Serialize)]
#[frb(non_opaque)]
pub struct SecureStorageStatus {
    pub backend: String,
    pub service: String,
    pub available: bool,
}

#[derive(Debug)]
pub enum SecureStorageError {
    Entry(String),
    Backend(String),
}

impl std::fmt::Display for SecureStorageError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Entry(error) => write!(formatter, "secure storage entry error: {error}"),
            Self::Backend(error) => write!(formatter, "secure storage backend error: {error}"),
        }
    }
}

impl std::error::Error for SecureStorageError {}

pub struct OsSecureSecretStore;

impl OsSecureSecretStore {
    pub fn status() -> SecureStorageStatus {
        let store = Self;

        storage_status_for(&store)
    }

    fn entry(key: &str) -> Result<Entry, SecureStorageError> {
        Self::entry_in(SERVICE_NAME, key)
    }

    fn entry_in(service: &str, key: &str) -> Result<Entry, SecureStorageError> {
        ensure_native_store()?;

        Entry::new(service, key).map_err(|error| SecureStorageError::Entry(error.to_string()))
    }

    /// Reads `key` from the legacy slot. Any failure means "nothing to
    /// migrate" -- the caller keeps the error from the current slot, which is
    /// the one worth surfacing.
    fn load_legacy(key: &str) -> Option<Vec<u8>> {
        Self::entry_in(LEGACY_SERVICE_NAME, key)
            .ok()?
            .get_secret()
            .ok()
    }
}

pub fn storage_status_for(_store: &dyn SecureSecretStore) -> SecureStorageStatus {
    SecureStorageStatus {
        backend: BACKEND_NAME.to_string(),
        service: SERVICE_NAME.to_string(),
        available: ensure_native_store().is_ok(),
    }
}

impl SecureSecretStore for OsSecureSecretStore {
    fn load_secret(&self, key: &str) -> Result<Vec<u8>, SecureStorageError> {
        let current = Self::entry(key)?
            .get_secret()
            .map_err(|error| SecureStorageError::Backend(error.to_string()));
        let Err(error) = current else {
            return current;
        };

        // Nothing under this app's own slot. Before surfacing the failure --
        // which fails the whole runtime closed when a database exists -- take
        // the one-time hand-off from the slot this app used to share with the
        // Tauri shell. Falling back on ANY error, not just a typed
        // not-found, keeps this independent of the backend's error taxonomy;
        // if the legacy slot is empty too, the original error is returned
        // unchanged.
        #[cfg(target_os = "macos")]
        if let Some(secret) = Self::load_from_legacy_keychain(key) {
            // Best-effort migration: a write failure still lets this run
            // proceed with the recovered secret, and the next start retries
            // the copy.
            let _ = self.save_secret(key, &secret);
            return Ok(secret);
        }
        let Some(secret) = Self::load_legacy(key) else {
            return Err(error);
        };
        // Best-effort migration: a write failure still lets this run proceed
        // with the recovered secret, and the next start retries the copy.
        let _ = self.save_secret(key, &secret);

        Ok(secret)
    }

    fn save_secret(&self, key: &str, value: &[u8]) -> Result<(), SecureStorageError> {
        Self::entry(key)?
            .set_secret(value)
            .map_err(|error| SecureStorageError::Backend(error.to_string()))
    }

    fn delete_secret(&self, key: &str) -> Result<(), SecureStorageError> {
        Self::entry(key)?
            .delete_credential()
            .map_err(|error| SecureStorageError::Backend(error.to_string()))
    }
}

/// Runs `init` and caches a `()` marker only on success. A failure is returned
/// without being memoized, so a transient error (locked keychain at boot) is
/// retried on the next call instead of poisoning the store for the process.
/// Only the keychain-backed hosts memoize anything; Android never enters the
/// store (see `ensure_native_store`).
#[cfg(not(target_os = "android"))]
fn cache_on_success<E>(cell: &OnceLock<()>, init: impl FnOnce() -> Result<(), E>) -> Result<(), E> {
    if cell.get().is_some() {
        return Ok(());
    }
    let result = init();
    if result.is_ok() {
        let _ = cell.set(());
    }
    result
}

/// Android has no keyring-backed store to install. `keyring::use_native_store`
/// would build the Android Keystore store, whose vault lookup makes JNI calls
/// while holding a process-global mutex; with no Android `Context` wired into
/// that crate the call panics, and the panic poisons that global for the rest
/// of the process. Every later call -- including the diagnostics read behind
/// the "History status" banner -- then dies on `PoisonError` instead of
/// returning a status. Nothing on Android needs the store anyway: the DEK is
/// injected and `construct_resources` opens the database with it, so refuse
/// here and never enter the crate.
#[cfg(target_os = "android")]
fn ensure_native_store() -> Result<(), SecureStorageError> {
    Err(SecureStorageError::Backend(NATIVE_STORE_ERROR.to_string()))
}

#[cfg(not(target_os = "android"))]
fn ensure_native_store() -> Result<(), SecureStorageError> {
    static NATIVE_STORE: OnceLock<()> = OnceLock::new();

    cache_on_success(&NATIVE_STORE, select_native_store)
        .map_err(|error| SecureStorageError::Backend(format!("{NATIVE_STORE_ERROR}: {error}")))
}

/// Picks the process-default credential store. On macOS a sandboxed build
/// (both DebugProfile and Release entitlements enable the sandbox) prefers
/// the data-protection keychain, the store Apple designed for sandboxed
/// apps: it never shows the legacy login-keychain access prompt an
/// ad-hoc-signed build can hit at every launch. A set/get/delete probe
/// proves the store accepts items before committing; a failure falls back
/// to the legacy store so behavior never regresses.
#[cfg(not(target_os = "android"))]
fn select_native_store() -> Result<(), SecureStorageError> {
    #[cfg(target_os = "macos")]
    {
        if std::env::var_os("APP_SANDBOX_CONTAINER_ID").is_some() {
            return select_sandboxed_mac_store();
        }
    }
    keyring::use_native_store(false)
        .map_err(|error| SecureStorageError::Backend(format!("{NATIVE_STORE_ERROR}: {error}")))
}

/// Whether the sandboxed macOS build runs on the protected store and so
/// needs the one-time legacy hand-over in `load_secret`. False until
/// `select_sandboxed_mac_store` succeeds.

#[cfg(target_os = "macos")]
static PROTECTED_STORE_ACTIVE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

#[cfg(target_os = "macos")]
fn protected_store_active() -> bool {
    std::sync::atomic::AtomicBool::load(
        &PROTECTED_STORE_ACTIVE,
        std::sync::atomic::Ordering::Acquire,
    )
}

/// Selects the data-protection keychain for a sandboxed macOS build,
/// proving it works with a real roundtrip first. The probe key is unique
/// per launch so the created item is always fresh — a stale probe item
/// created by a different build could ACL-prompt instead.

#[cfg(target_os = "macos")]
fn select_sandboxed_mac_store() -> Result<(), SecureStorageError> {
    use std::sync::atomic::Ordering;
    use std::time::{SystemTime, UNIX_EPOCH};

    let probe_key = format!(
        "store-probe-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default()
    );
    let probe = probe_protected_store(&probe_key);
    if let Err(error) = probe {
        dlog::write(
            LogLevel::Warn,
            kinds::IDENTITY,
            SERVICE_NAME,
            &format!("protected keychain store unavailable ({error}); using legacy keychain store"),
        );
        PROTECTED_STORE_ACTIVE.store(false, Ordering::Release);
        return keyring::use_native_store(false).map_err(|error| {
            SecureStorageError::Backend(format!("{NATIVE_STORE_ERROR}: {error}"))
        });
    }
    PROTECTED_STORE_ACTIVE.store(true, Ordering::Release);
    dlog::write(
        LogLevel::Info,
        kinds::IDENTITY,
        SERVICE_NAME,
        "macOS sandboxed: protected keychain store selected",
    );
    Ok(())
}

/// A set/get/delete roundtrip in the data-protection keychain. Ad-hoc
/// signing can be rejected by entitlement checks that only surface on a
/// real write, so the store is proven before the DEK is trusted to it.

#[cfg(target_os = "macos")]
fn probe_protected_store(probe_key: &str) -> Result<(), SecureStorageError> {
    let probe_service = format!("{SERVICE_NAME}.probe");
    const PROBE_VALUE: &[u8] = b"mosh";
    let entry = Entry::new(&probe_service, probe_key)
        .map_err(|error| SecureStorageError::Entry(error.to_string()))?;
    let outcome = (|| -> Result<(), SecureStorageError> {
        entry
            .set_secret(PROBE_VALUE)
            .map_err(|error| SecureStorageError::Backend(error.to_string()))?;
        let read = entry
            .get_secret()
            .map_err(|error| SecureStorageError::Backend(error.to_string()))?;
        if read != PROBE_VALUE {
            return Err(SecureStorageError::Backend(
                "protected store probe roundtrip mismatch".to_string(),
            ));
        }
        entry
            .delete_credential()
            .map_err(|error| SecureStorageError::Backend(error.to_string()))
    })();
    // Leave nothing behind even when the roundtrip failed midway.
    if outcome.is_err() {
        let _ = entry.delete_credential();
    }
    outcome
}

/// One-time hand-over for a sandboxed macOS build whose DEK still lives in
/// the legacy login-keychain slots: reads them while the legacy store is
/// the process default, then restores the data-protection store. The
/// keychain is only touched from `Persistence::open` (once per process,
/// behind the resources OnceLock), so the brief default-store swap is
/// single-threaded by construction.

#[cfg(target_os = "macos")]
fn load_from_legacy_keychain(key: &str) -> Option<Vec<u8>> {
    if !protected_store_active() {
        return None; // already on the legacy store; the normal fallback covers it
    }
    keyring::use_named_store("keychain").ok()?;
    let current = OsSecureSecretStore::entry_in(SERVICE_NAME, key)
        .ok()
        .and_then(|entry| entry.get_secret().ok());
    let tauri = if current.is_none() {
        OsSecureSecretStore::entry_in(LEGACY_SERVICE_NAME, key)
            .ok()
            .and_then(|entry| entry.get_secret().ok())
    } else {
        None
    };
    let secret = current.or(tauri);
    if keyring::use_named_store("protected").is_err() {
        dlog::write(
            LogLevel::Warn,
            kinds::IDENTITY,
            SERVICE_NAME,
            "could not restore the protected keychain store after the legacy read",
        );
    }
    if secret.is_some() {
        dlog::write(
            LogLevel::Info,
            kinds::IDENTITY,
            SERVICE_NAME,
            "migrating secret from the legacy macOS keychain into the protected store",
        );
    }
    secret
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_SECRET_KEY: &str = "adapter-contract-test-secret";

    #[test]
    fn native_store_roundtrip_preserves_secret_bytes() {
        let store = OsSecureSecretStore;
        let secret = [0, 1, 2, 15, 16, 255];

        store
            .save_secret(TEST_SECRET_KEY, &secret)
            .expect("native store should save secret");
        let loaded = store
            .load_secret(TEST_SECRET_KEY)
            .expect("native store should load secret");
        store
            .delete_secret(TEST_SECRET_KEY)
            .expect("native store should delete secret");

        assert_eq!(loaded, secret);
    }

    #[test]
    fn cache_on_success_retries_after_error_then_caches() {
        static CELL: OnceLock<()> = OnceLock::new();
        // A transient failure must NOT be memoized.
        assert!(cache_on_success(&CELL, || Err::<(), &str>("transient")).is_err());
        // A later success caches the result.
        assert!(cache_on_success(&CELL, || Ok::<(), &str>(())).is_ok());
        // Once cached, the init closure is never run again.
        assert!(cache_on_success(&CELL, || -> Result<(), &str> {
            panic!("init must not run once cached")
        })
        .is_ok());
    }

    /// The rename is only safe because a DEK already sitting in the shared
    /// Tauri slot is handed forward. Without this the fail-closed guard in
    /// `Persistence::open` would brick every install that had one.
    #[test]
    fn load_falls_back_to_the_legacy_slot_and_migrates_it() {
        const KEY: &str = "adapter-contract-legacy-migration";
        let store = OsSecureSecretStore;
        let secret = [7u8, 8, 9, 250];

        // Seed ONLY the legacy slot, exactly like an install predating the
        // rename.
        OsSecureSecretStore::entry_in(LEGACY_SERVICE_NAME, KEY)
            .expect("legacy entry")
            .set_secret(&secret)
            .expect("legacy slot should accept the secret");

        let loaded = store
            .load_secret(KEY)
            .expect("a legacy secret must still be readable after the rename");
        assert_eq!(loaded, secret);

        // ...and it is copied into this app's own slot, so the next read no
        // longer depends on the legacy one.
        let migrated = OsSecureSecretStore::entry_in(SERVICE_NAME, KEY)
            .expect("current entry")
            .get_secret()
            .expect("the secret should have been migrated forward");
        assert_eq!(migrated, secret);

        let _ = store.delete_secret(KEY);
        let _ = OsSecureSecretStore::entry_in(LEGACY_SERVICE_NAME, KEY)
            .expect("legacy entry")
            .delete_credential();
    }

    #[test]
    fn status_describes_native_backend() {
        let status = OsSecureSecretStore::status();

        assert_eq!(status.backend, BACKEND_NAME);
        assert_eq!(status.service, SERVICE_NAME);
        assert!(status.available);
    }
}
