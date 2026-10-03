use crate::api::shared_runtime::resolve_data_dir;
use crate::moss_ffi::{
    clear_moss_keystore, set_moss_keystore, MossFfiRuntime, MossNodeConfig, MOSS_TEST_LOCK,
};
use crate::persistence::Persistence;
use crate::secure_storage::{OsSecureSecretStore, SecureSecretStore};
use std::sync::Arc;

// A keychain key unique to this test run.
//
// This test used to mint and then DELETE the production key
// ("history-dek-v1") on teardown, meaning any `cargo test` destroyed the
// DEK of whoever ran it: their real history.redb stayed on disk encrypted
// with a key that no longer existed, so every later app start failed
// closed with "DEK unavailable but database exists" and the history was
// unrecoverable. Per-run key + `open_with_key` keeps the real keychain
// path under test while leaving the production entry alone.
/// Deletes itself from the host keychain on drop, so a PANICKING test
/// still cleans up. An explicit teardown call is skipped on unwind, which
/// would leave one stray credential behind per failed run.
struct TestDekKey(String);

impl TestDekKey {
    fn new() -> Self {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default();
        Self(format!("history-dek-test-{}-{nanos}", std::process::id()))
    }

    fn as_str(&self) -> &str {
        &self.0
    }
}

impl Drop for TestDekKey {
    fn drop(&mut self) {
        let _ = OsSecureSecretStore.delete_secret(&self.0);
    }
}

/// Build a minimal config for a lone node: a random-ish port in a range the
/// other tests do not use, no static peers. Identity is resolved at init
/// time, so the node never needs to actually exchange traffic here.
fn lone_node_config(port: u16) -> MossNodeConfig {
    MossNodeConfig {
        listen_port: port,
        static_peer: None,
        bind_interface: None,
    }
}

/// A unique temp dir per run so two invocations (or a leftover from a prior
/// run) never collide. Caller removes it in teardown.
fn unique_test_dir(label: &str) -> std::path::PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "mosh-m2-test-{label}-{}-{nanos}",
        std::process::id()
    ))
}

/// Load Moss, open Persistence at `dir/history.redb`, register + install the
/// keystore, init + start a node, and return its public key hex (the stable
/// transport identity). Mirrors `construct_runtime`'s ordering: keystore is
/// installed BEFORE init so Moss loads any existing identity instead of
/// minting a fresh one.
fn load_identity_at(
    dir: &std::path::Path,
    port: u16,
    mesh_id: &str,
    dek_key: &str,
) -> (Arc<MossFfiRuntime>, Arc<Persistence>, String) {
    let persistence = Arc::new(
        Persistence::open_with_key(&dir.join("history.redb"), dek_key)
            .expect("persistence should open"),
    );
    let moss = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    // Register the keystore + install the C callbacks BEFORE init_node, so
    // Moss resolves identity from the registered store.
    set_moss_keystore(persistence.clone());
    moss.install_keystore().expect("keystore should install");
    let node = moss
        .init_default_node(mesh_id, &lone_node_config(port))
        .expect("node should init");
    node.start().expect("node should start");
    let key = node
        .public_key_hex()
        .expect("node should expose its public key");
    (moss, persistence, key)
}

// First real consumer of OsSecureSecretStore (ADR 0011): prove the redb
// at-rest store + the Moss transport-identity keystore survive a restart
// when wired the way `construct_runtime` wires them. Uses the live Moss
// library and the live Windows Credential Manager on this host, so it
// needs moss.dll present (npm run moss:prepare) and is gated by
// MOSS_TEST_LOCK like the other live-Moss tests. Serial under
// --test-threads=1.
#[test]
fn persistence_and_identity_survive_restart() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let dir = unique_test_dir("identity");
    std::fs::create_dir_all(&dir).expect("test dir should create");
    let mesh_id = "mosh-m2-identity-test";
    let port = 43050u16;
    let dek_key = TestDekKey::new();

    // --- Load #1: first run, keystore empty -> Moss mints an identity,
    // saves it through the keystore into the encrypted redb store. Also
    // persist a history blob so we can prove it round-trips after reopen.
    let (_moss1, p1, identity_a) = load_identity_at(&dir, port, mesh_id, dek_key.as_str());
    p1.put_session("m2-session", b"{\"hello\":\"restart\"}")
        .expect("session record should persist");
    // The keystore MUST have saved the identity for load #2 to reuse it.
    assert!(
        p1.get_moss_identity()
            .expect("identity read should succeed")
            .is_some(),
        "first run must have saved the transport identity through the keystore"
    );
    // --- Simulate a restart: release the process-global keystore (which
    // still holds a ref to p1, so the redb DB lock would otherwise stay
    // held), then drop p1 so the redb handle closes. The DEK stays in the
    // keychain and the DB file stays on disk -- the state a fresh
    // process sees. `clear_moss_keystore` is the test-only hook for the
    // "process exit drops the global" step; production never clears it.
    clear_moss_keystore();
    drop(p1);

    // --- Load #2: reopen the SAME path. Persistence::open must find the
    // existing DB AND the existing DEK in the keychain (it fail-closes if
    // the DEK is missing while the DB exists), then Moss must load -- not
    // mint -- the saved identity.
    let (moss2, p2, identity_b) = load_identity_at(&dir, port + 1, mesh_id, dek_key.as_str());

    assert_eq!(
        identity_a, identity_b,
        "transport identity must survive restart (loaded, not regenerated)"
    );

    // The persisted history blob must decrypt under the reopened DEK.
    let sessions = p2.list_sessions().expect("sessions should list");
    assert!(
        sessions.iter().any(|row| row == b"{\"hello\":\"restart\"}"),
        "persisted session record must round-trip and decrypt after reopen: {sessions:?}"
    );

    // --- Teardown (restores the pre-test process state so unrelated Moss
    // tests in this binary are not contaminated):
    //   1. Uninstall the Go-side keystore callbacks. Moss_SetKeyStore is a
    //      Go-process-global; once installed here it stays live for every
    //      later init_node in the same test binary. Uninstalling reverts
    //      Moss to its baseline "callbacks nil -> mint a fresh identity
    //      per node" behavior. Without this, a later test that loads the
    //      Rust MOSS_KEYSTORE global (e.g. the moss_ffi MemStore test, which
    //      leaves a saved identity in the global and never clears it) would
    //      feed that stale identity to every later node, collapsing all
    //      their peer ids to one and failing connect-to-counterpart
    //      assertions.
    //   2. Clear the Rust keystore global (belt-and-suspenders; inert once
    //      the Go callbacks are gone, but keeps the Rust state clean).
    //   3. Remove the unique temp dir.
    //
    // This run's DEK is NOT listed: `TestDekKey` deletes it on drop, which
    // also covers the panicking path this explicit teardown would skip.
    let _ = moss2.uninstall_keystore();
    clear_moss_keystore();
    let _ = std::fs::remove_dir_all(&dir);
}

// M-5 (ADR 0010): unit tests for the app_data_dir bridge. The
// path-selection logic is exercised through the pure `resolve_data_dir`
// helper (no process-global mutation), so it stays fully isolated. The
// `set_app_data_dir` validation tests touch the real `APP_DATA_DIR`
// `OnceLock`: the empty-reject test returns Err BEFORE the cell is touched
// (the `trim().is_empty()` guard is first), so it never mutates state; the
// double-set test DOES set the cell on its first call, but the cell is
// inert in the test binary -- no test here exercises `construct_runtime`
// (the only reader of `APP_DATA_DIR`), and production never runs in a test
// binary -- so leaving it set cannot contaminate the other 218 tests. The
// dir it sets to is a unique temp subdir so even a hypothetical future
// reader would point at an isolated, real path.

#[test]
fn resolve_data_dir_uses_injected_app_data_dir() {
    let injected = unique_test_dir("app_data_dir");
    let resolved = resolve_data_dir(Some(&injected));
    assert_eq!(
        resolved,
        injected.join("mosh"),
        "resolve_data_dir must open under <app_data_dir>/mosh when injected"
    );
    let _ = std::fs::remove_dir_all(&injected);
}

#[test]
fn resolve_data_dir_falls_back_to_temp_when_not_injected() {
    let resolved = resolve_data_dir(None);
    assert_eq!(
        resolved,
        std::env::temp_dir().join("mosh"),
        "resolve_data_dir must fall back to temp/mosh when no dir is injected"
    );
}

#[test]
fn set_app_data_dir_rejects_empty_path() {
    // Empty (and whitespace-only) paths must be rejected BEFORE the cell
    // is touched, so this test never mutates the process global and stays
    // isolated from the other tests.
    assert!(
        super::set_app_data_dir(String::new()).is_err(),
        "set_app_data_dir must reject an empty path"
    );
    assert!(
        super::set_app_data_dir("   ".to_string()).is_err(),
        "set_app_data_dir must reject a whitespace-only path"
    );
}

#[test]
fn set_app_data_dir_is_idempotent_for_same_value_and_rejects_divergence() {
    // Idempotent-on-same-value: a re-inject of the SAME path is a no-op
    // (Ok), since Android re-runs main() on activity recreation in a live
    // process and a fresh Dart isolate cannot tell the inject already
    // happened. A DIFFERENT path is a real divergence (Dart's DB-exists
    // check vs the path Rust opened under) and must still Err. This test
    // sets the process-global cell (OnceLock is irreversible), but the
    // cell is inert in the test binary -- no test exercises
    // `construct_runtime` (its only reader) -- so leaving it set cannot
    // contaminate the other tests. The dir is a unique temp subdir so a
    // hypothetical future reader would point at an isolated, real path.
    let dir = unique_test_dir("app_data_dir_set");
    std::fs::create_dir_all(&dir).expect("test dir should create");
    assert!(
        super::set_app_data_dir(dir.to_string_lossy().to_string()).is_ok(),
        "first set_app_data_dir call must succeed"
    );
    assert!(
        super::set_app_data_dir(dir.to_string_lossy().to_string()).is_ok(),
        "re-inject of the SAME path must be a no-op (Ok)"
    );
    let other = unique_test_dir("app_data_dir_set_other");
    assert!(
        super::set_app_data_dir(other.to_string_lossy().to_string()).is_err(),
        "set_app_data_dir with a DIFFERENT path must be rejected (divergence)"
    );
    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&other);
}
