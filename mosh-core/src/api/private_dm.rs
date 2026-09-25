//! Private-DM facade: the DM-specific bridge operations.
//!
//! Invite create/accept, session poll/list, the voice-call pipeline
//! (start/accept/decline/end/send-frame/drain-frames) and the two mobile
//! inject knobs. The actions every conversation kind shares — send, retry,
//! attachment send/download/cancel, leave — live once in
//! `api::conversation` (ADR 0024) and borrow this facade's runtime lock
//! through `ensure_runtime()`. Everything is call/response over the
//! bridge — poll-based, no StreamSink; the Dart side polls snapshots
//! on a cadence.
//!
//! OWNERSHIP (ADR 0016 — api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<PrivateDmRuntime>>>` plus a cached
//! `load_error`. `ensure_runtime()` constructs the singleton on first
//! call, then locks and borrows it. Every function that drives the
//! runtime calls
//! `ensure_runtime()` and delegates. The actions (invites, call controls)
//! return the typed `ConversationBridgeError` (ADR 0024) so Dart can branch
//! on the kind; the reads and the voice-frame pump keep the plain `String`
//! shape (ADR 0010). The two inject knobs below touch `api::shared_runtime`
//! instead.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the request/return types are the
//! runtime's own, re-exported here via `use crate::private_dm_runtime::{...}`.
//! They are NOT redefined.
//!
//! PERSISTENCE: `construct_runtime` opens the encrypted at-rest store and
//! wires the Moss transport-identity keystore -- `Persistence::open(...)` -> `set_moss_keystore` ->
//! `install_keystore` (before any node starts) -> `from_shared_node(...,
//! Some(persistence))` -> `rehydrate()`. Conversations AND the device
//! identity now survive restart (ADR 0011 SecureSecretStore: this is the
//! first real consumer of `OsSecureSecretStore`, i.e. the Windows Credential
//! Manager on this host; the mobile platform channel stays deferred). The
//! api facade owns no app handle, so the DB path mirrors the AttachmentStore
//! fallback exactly: a `mosh` dir under `std::env::temp_dir()`, file
//! `history.redb`. A real `app_data_dir` arrives via the ADR 0010 bridge
//! (M-5: `set_app_data_dir`, called by Dart at startup on every platform
//! via `getApplicationSupportDirectory`). When injected, both the history
//! DB and the AttachmentStore live under that app-private dir instead of
//! temp; the temp fallback remains for tests and any caller that does not
//! inject (e.g. a host without the path_provider plugin). Persistence
//! opens fail-closed (`PersistenceError` ->
//! `PrivateDmRuntimeError::Persistence`): a desktop app that silently drops
//! every conversation on restart is worse than a surfaced error.
//!
//! TESTING: `ensure_runtime()` calls `MossFfiRuntime::load_default()`, which
//! loads the Moss shared library. There is no way to exercise any public
//! function without triggering that load, so a unit test here would require
//! the Moss to be present and would fail in CI without it. The persistence
//! + keystore wiring IS unit/integration-tested
//! here (`persistence_and_identity_survive_restart`): it loads the live
//! Moss lib, opens a real `Persistence` via the `OsSecureSecretStore`
//! (Windows Credential Manager on this host), and proves the transport
//! identity + a history blob survive a drop-and-reopen -- cleaning its DEK
//! out of the keychain in teardown so the host keychain is not polluted.

use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::private_dm_runtime::{
    AcceptInviteRequest, CallMedia, CallStarted, InviteCreated, PrivateDmRuntime,
    PrivateDmRuntimeError, SessionListSnapshot, SessionSnapshot, StartSessionRequest,
};

const PRIVATE_DM_UNAVAILABLE: &str = "private DM runtime unavailable";
const LOCK_POISONED: &str = "private DM runtime lock poisoned";

/// Process-global singleton for the private-DM runtime (ADR 0016).
///
/// `Option` carries the "ready vs missing" duality: `Some` once Moss
/// loaded, `None` if construction failed (so later calls report the
/// original error instead of retrying into the same failure). The `OnceLock` guarantees a single
/// construction; the `Mutex` serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<PrivateDmRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call.
static LOAD_ERROR: OnceLock<String> = OnceLock::new();
// The two mobile-inject knobs (`set_history_dek`, `set_app_data_dir`) +
// the shared Moss node / attachment store / persistence are owned by
// `api::shared_runtime` (ADR 0016 shared-runtime refactor). This facade
// keeps the frb-bound `set_history_dek` / `set_app_data_dir` wrappers so
// the Dart bridge paths (`package:.../rust/api/private_dm.dart`) stay
// stable; the bodies delegate one line each.

/// Inject the at-rest history DEK from the mobile platform channel (ADR
/// 0011). See `api::shared_runtime::set_history_dek` for the full
/// contract. This wrapper is frb-bound so the Dart startup path keeps
/// the stable `crate::api::private_dm::set_history_dek` symbol.
pub fn set_history_dek(dek: Vec<u8>) -> Result<(), String> {
    crate::api::shared_runtime::set_history_dek(dek)
}

/// Inject the app-private data directory from the platform channel (ADR
/// 0010, M-5). See `api::shared_runtime::set_app_data_dir` for the full
/// contract. This wrapper is frb-bound so the Dart startup path keeps
/// the stable `crate::api::private_dm::set_app_data_dir` symbol.
pub fn set_app_data_dir(path: String) -> Result<(), String> {
    crate::api::shared_runtime::set_app_data_dir(path)
}

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: load the shared resources (Moss node + attachment
/// store + persistence via `api::shared_runtime`), build the DM runtime
/// off them, rehydrate saved conversations, and store it. On every later
/// call: just lock. Returns a guard the public functions can drive the
/// `&mut self` runtime through, or an `Unavailable` bridge error.
pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, Option<PrivateDmRuntime>>, ConversationBridgeError> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex
        .lock()
        .map_err(|_| ConversationBridgeError::unavailable(LOCK_POISONED))?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{PRIVATE_DM_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| PRIVATE_DM_UNAVAILABLE.to_string());
        return Err(ConversationBridgeError::unavailable(message));
    }
    Ok(guard)
}

/// Build the singleton value once. Returns `Some(runtime)` on success, or
/// `None` + caches the cause in `LOAD_ERROR` on failure. Split out from
/// `ensure_runtime` to keep that function's nesting shallow.
fn build_runtime() -> Option<PrivateDmRuntime> {
    match construct_runtime() {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            let _ = LOAD_ERROR.set(error.to_string());
            None
        }
    }
}

/// The DM-runtime construction recipe: borrow the shared resources (Moss
/// node + attachment store + persistence) from `api::shared_runtime`,
/// build a `PrivateDmRuntime::from_shared_node` off them, then rehydrate
/// saved conversations from the encrypted store. The shared setup (Moss
/// load, keystore install, persistence open, attachment store) lives in
/// `shared_runtime::construct_resources` -- DM/channel/group all share
/// it.
fn construct_runtime() -> Result<PrivateDmRuntime, PrivateDmRuntimeError> {
    let resources = crate::api::shared_runtime::ensure_shared_resources()
        .map_err(PrivateDmRuntimeError::Moss)?;
    let mut runtime = PrivateDmRuntime::from_shared_node(
        resources.shared_node,
        resources.attachment_store,
        resources.persistence,
    );
    // Rehydrate saved conversations from the encrypted store; with
    // persistence wired it now rebuilds sessions + history instead of the
    // slice-one no-op.
    runtime.rehydrate();
    Ok(runtime)
}

/// Create a private-DM invite. The inviter publishes a KeyPackage and an invite URI.
pub fn create_invite(
    request: StartSessionRequest,
) -> Result<InviteCreated, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .create_invite(request)
        .map_err(ConversationBridgeError::from)
}

/// Accept a private-DM invite. The
/// joiner parses the invite URI and processes the inviter's Welcome.
pub fn accept_invite(
    request: AcceptInviteRequest,
) -> Result<SessionSnapshot, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .accept_invite(request)
        .map_err(ConversationBridgeError::from)
}

/// Poll a session for its current snapshot. The Dart side calls this
/// on a poll cadence; no push, no StreamSink.
pub fn poll_session(session_id: String) -> Result<SessionSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .poll_session(&session_id)
        .map_err(|error| error.to_string())
}

/// List all sessions and their snapshots.
pub fn list_sessions() -> Result<SessionListSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list_sessions().map_err(|error| error.to_string())
}

/// Start a voice call in a DM session. Mints the call id + the
/// symmetric call key + nonce prefix, publishes a CallOffer to the peer
/// over the session MLS channel, and moves the session into the
/// outgoing-ringing state (SessionSnapshot.outgoing_call). The bridge
/// returns CallStarted so the caller can begin capturing + sealing frames.
pub fn call_start(session_id: String) -> Result<CallStarted, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .call_start(&session_id)
        .map_err(ConversationBridgeError::from)
}

/// Accept an incoming voice call.
/// Moves the session from pending-call into the active state. The peer
/// learns the acceptance through the MLS CallAccept control message.
pub fn call_accept(session_id: String, call_id: String) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .call_accept(&session_id, &call_id)
        .map_err(ConversationBridgeError::from)
}

/// Decline an incoming voice call.
/// Publishes a CallDecline control message with the reason; the session
/// returns to its idle state.
pub fn call_decline(
    session_id: String,
    call_id: String,
    reason: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .call_decline(&session_id, &call_id, &reason)
        .map_err(ConversationBridgeError::from)
}

/// End an active or ringing voice call.
/// Publishes a CallEnd control message with the reason; the session
/// returns to idle and the CallEvent is recorded for the call log.
pub fn call_end(
    session_id: String,
    call_id: String,
    reason: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .call_end(&session_id, &call_id, &reason)
        .map_err(ConversationBridgeError::from)
}

/// The call media hub, cached after the first call so the 20 ms audio loop
/// never takes the runtime lock again.
fn call_media() -> Result<Arc<CallMedia>, String> {
    static CALL_MEDIA: OnceLock<Arc<CallMedia>> = OnceLock::new();
    if let Some(media) = CALL_MEDIA.get() {
        return Ok(Arc::clone(media));
    }
    let guard = ensure_runtime().map_err(|error| error.to_string())?;
    let media = guard
        .as_ref()
        .expect("ensure_runtime guarantees Some")
        .call_media();
    Ok(Arc::clone(CALL_MEDIA.get_or_init(|| media)))
}

/// Publish one sealed voice-call frame for an active call. The Dart capture
/// loop drives it every 20 ms; the caller seals the frame before sending.
/// A call id is unique on its own; `session_id` stays for the bridge
/// contract.
pub fn call_send_frame(session_id: String, call_id: String, frame: Vec<u8>) -> Result<(), String> {
    let _ = session_id;
    call_media()?.send(&call_id, &frame)
}

/// The sealed frames the peer sent for an active call since the last drain.
/// The Dart playback loop drives it every 20 ms, then opens the frames and
/// queues them into the jitter buffer.
pub fn call_drain_frames(session_id: String, call_id: String) -> Result<Vec<Vec<u8>>, String> {
    let _ = session_id;
    Ok(call_media()?.drain(&call_id))
}

/// Whether this user sends read receipts (and therefore sees others').
/// One app-level answer covering every DM; read from the plain JSON
/// settings file in the data dir, default off. Does not construct the
/// runtime: the setting is a file read, not a runtime action, so the
/// settings screen can show it before any session exists.
pub fn read_receipts_enabled() -> bool {
    crate::read_receipts::load(&crate::api::shared_runtime::resolved_data_dir())
        .map(|setting| setting.enabled)
        .unwrap_or(false)
}

/// Set the app-level read-receipts answer. Persists BOTH ways (an "off" is
/// a decision too), then applies it to the runtime so inbound receipts are
/// honored or dropped from this moment. Constructs the runtime when it is
/// not up yet — a settings screen may toggle before any session exists,
/// and the runtime reads the file at every use anyway, so a construction
/// failure only means the value is already on disk.
pub fn set_read_receipts_enabled(enabled: bool) -> Result<(), String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .set_read_receipts_enabled(enabled)
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
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
}
