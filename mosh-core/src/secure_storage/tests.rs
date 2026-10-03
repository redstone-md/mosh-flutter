#[test]
fn only_a_missing_entitlement_is_an_expected_fallback() {
    use super::protected_store_fallback_level as level;
    use crate::diagnostics_log::LogLevel;
    assert_eq!(
        level("Platform secure storage failure: A required entitlement isn't present."),
        LogLevel::Info
    );
    assert_eq!(level("OSStatus -34018"), LogLevel::Info);
    assert_eq!(level("User interaction is not allowed."), LogLevel::Warn);
}

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

/// The rename is only safe because a DEK already sitting in the legacy
/// slot is handed forward. Without this the fail-closed guard in
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
