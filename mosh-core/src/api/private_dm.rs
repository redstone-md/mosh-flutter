//! Private-DM facade.
//!
//! Surfaces the former `private_dm_*` Tauri command group: invite
//! create/accept, message send/retry, session poll/list/close,
//! attachment send/download/cancel, and voice-call start/accept/decline/
//! end/send-frame/drain-frames. Call-start and frame-drain map to
//! `StreamSink`-returning facade functions, mirroring the former Tauri
//! events that streamed call signaling and media frames.
//!
//! Slice one (S1.4) ports only the poll-based subset: invite create/accept,
//! message send, session poll/list/close. There were no Tauri events for
//! private_dm — the React frontend polled snapshots every AUTO_POLL_MS — so
//! this slice has NO StreamSink function. Attachment and voice-call slices
//! (which DID stream frames in the Tauri shell) arrive later.
//!
//! OWNERSHIP (ADR 0016 — api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<PrivateDmRuntime>>>`. This replaces the Tauri
//! shell's `PrivateDmState` (a managed struct whose
//! `runtime: Mutex<Option<...>>` + `load_error` pair). `ensure_runtime()` is
//! the analogue of `PrivateDmState::ready` (construction) + `with_runtime`
//! (lock + borrow). Each public function calls `ensure_runtime()` and
//! delegates, mapping `PrivateDmRuntimeError` to a plain `String` so the
//! bridge surfaces it as a Dart exception (ADR 0010).
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the request/return types are the
//! runtime's own, re-exported here via `use crate::private_dm_runtime::{...}`.
//! They are NOT redefined. `Result<T, String>` matches the Tauri command
//! shape exactly.
//!
//! PERSISTENCE: `construct_runtime` opens the encrypted at-rest store and
//! wires the Moss transport-identity keystore the same way the Tauri shell
//! did in `setup()` -- `Persistence::open(...)` -> `set_moss_keystore` ->
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
//! loads the Moss shared library. There is no way to exercise ANY of the
//! six public functions without triggering that load, so a unit test here
//! would require the Moss lib to be present and would fail in CI without
//! it. The six public functions are integration-tested in S2/S5 (live
//! Moss). The persistence + keystore wiring IS unit/integration-tested
//! here (`persistence_and_identity_survive_restart`): it loads the live
//! Moss lib, opens a real `Persistence` via the `OsSecureSecretStore`
//! (Windows Credential Manager on this host), and proves the transport
//! identity + a history blob survive a drop-and-reopen -- cleaning its DEK
//! out of the keychain in teardown so the host keychain is not polluted.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::private_dm_runtime::{
    AcceptInviteRequest, CloseSessionResult, InviteCreated, PrivateDmRuntime,
    PrivateDmRuntimeError, SendMessageResult, SessionListSnapshot, SessionSnapshot,
    StartSessionRequest,
};
use crate::private_dm_runtime::{AttachmentSendResult, VoiceMeta};

// Mirrors the Tauri shell's `PRIVATE_DM_UNAVAILABLE` constant so the error
// string is byte-identical across the old and new shells.
const PRIVATE_DM_UNAVAILABLE: &str = "private DM runtime unavailable";
const LOCK_POISONED: &str = "private DM runtime lock poisoned";

/// Process-global singleton for the private-DM runtime (ADR 0016).
///
/// `Option` carries the same "ready vs missing" duality the Tauri shell's
/// `PrivateDmState` did: `Some` once Moss loaded, `None` if construction
/// failed (so later calls report the original error instead of retrying
/// into the same failure). The `OnceLock` guarantees a single
/// construction; the `Mutex` serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<PrivateDmRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call (the Tauri shell kept this in
/// `PrivateDmState::load_error`).
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
/// `&mut self` runtime through, or an error string matching the Tauri
/// shell's `unavailable_message` shape.
pub(crate) fn ensure_runtime() -> Result<MutexGuard<'static, Option<PrivateDmRuntime>>, String> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex.lock().map_err(|_| LOCK_POISONED.to_string())?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{PRIVATE_DM_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| PRIVATE_DM_UNAVAILABLE.to_string());
        return Err(message);
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
        .map_err(|error| PrivateDmRuntimeError::Moss(error))?;
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

/// Create a private-DM invite (1:1 port of the `private_dm_create_invite`
/// Tauri command). The inviter publishes a KeyPackage and an invite URI.
pub fn create_invite(request: StartSessionRequest) -> Result<InviteCreated, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .create_invite(request)
        .map_err(|error| error.to_string())
}

/// Accept a private-DM invite (1:1 port of `private_dm_accept_invite`). The
/// joiner parses the invite URI and processes the inviter's Welcome.
pub fn accept_invite(request: AcceptInviteRequest) -> Result<SessionSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .accept_invite(request)
        .map_err(|error| error.to_string())
}

/// Send a message into a session (1:1 port of `private_dm_send_message`).
pub fn send_message(session_id: String, body: String) -> Result<SendMessageResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_message(&session_id, body)
        .map_err(|error| error.to_string())
}

/// Retry a failed outbound message (1:1 port of `private_dm_retry_message`,
/// src-tauri/src/lib.rs L359-369). Re-sends a failed outbound message by
/// its message id; returns the send result (new delivery status) the
/// bridge caller uses to invalidate its snapshot so the next poll
/// re-renders the row. Mirrors React `retryDmMessage`
/// (native-messaging-gateway.ts) and the channel/group retry facades
/// (`channel::retry_message`, `private_group::retry_message`).
pub fn retry_message(session_id: String, message_id: String) -> Result<SendMessageResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .retry_message(&session_id, &message_id)
        .map_err(|error| error.to_string())
}

/// Poll a session for its current snapshot (1:1 port of
/// `private_dm_poll_session`). The React frontend called this every
/// AUTO_POLL_MS; no push, no StreamSink.
pub fn poll_session(session_id: String) -> Result<SessionSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .poll_session(&session_id)
        .map_err(|error| error.to_string())
}

/// List all sessions and their snapshots (1:1 port of
/// `private_dm_list_sessions`).
pub fn list_sessions() -> Result<SessionListSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list_sessions().map_err(|error| error.to_string())
}

/// Close and tear down a session (1:1 port of `private_dm_close_session`).
pub fn close_session(session_id: String) -> Result<CloseSessionResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .close_session(&session_id)
        .map_err(|error| error.to_string())
}

/// Begin (or retry) downloading a peer's attachment (1:1 port of
/// `private_dm_download_attachment`). Triggers the transfer; progress is
/// reported in the next `SessionSnapshot.attachments` poll.
pub fn download_attachment(session_id: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .download_attachment(&session_id, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Cancel an in-flight attachment transfer (1:1 port of
/// `private_dm_cancel_attachment`).
pub fn cancel_attachment(session_id: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .cancel_attachment(&session_id, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Send an attachment into a session (1:1 port of `private_dm_send_attachment`).
/// The bytes arrive base64-encoded (the bridge contract for all send_attachment
/// facades); decoded here before handing the raw `Vec<u8>` to the runtime,
/// matching the Tauri shell's `private_dm_send_attachment` (lib.rs L403-423).
/// `thumbnail_base64` is forwarded verbatim (the runtime stores it as-is for
/// the receiver's preview); `voice` is the optional `VoiceMeta` for voice
/// clips (None for plain files). Returns the new attachment's id + content
/// hash so the bridge caller can invalidate its snapshot.
pub fn send_attachment(
    session_id: String,
    file_name: String,
    mime: String,
    data_base64: String,
    thumbnail_base64: Option<String>,
    voice: Option<VoiceMeta>,
) -> Result<AttachmentSendResult, String> {
    let bytes = decode_base64(&data_base64)?;
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_attachment(&session_id, file_name, mime, bytes, thumbnail_base64, voice)
        .map_err(|error| error.to_string())
}

/// Decode a base64 string to raw bytes (1:1 port of the Tauri shell's
/// `decode_base64`, lib.rs L539-541). Uses the standard alphabet (the same
/// alphabet the React/Dart sides encode with -- `base64Encode`/`btoa`).
fn decode_base64(value: &str) -> Result<Vec<u8>, String> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD
        .decode(value)
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

    // The DEK key Persistence::open hardcodes (persistence.rs). The test mints
    // it on first open and MUST delete it from the host keychain on teardown so
    // it does not pollute the user's Windows Credential Manager. No other test
    // uses this key (existing persistence tests use open_with_dek, bypassing the
    // keychain), so there is no cross-test collision.
    const DEK_KEY: &str = "history-dek-v1";

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
    ) -> (Arc<MossFfiRuntime>, Arc<Persistence>, String) {
        let persistence = Arc::new(
            Persistence::open(&dir.join("history.redb")).expect("persistence should open"),
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

        // --- Load #1: first run, keystore empty -> Moss mints an identity,
        // saves it through the keystore into the encrypted redb store. Also
        // persist a history blob so we can prove it round-trips after reopen.
        let (_moss1, p1, identity_a) = load_identity_at(&dir, port, mesh_id);
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
        let (moss2, p2, identity_b) = load_identity_at(&dir, port + 1, mesh_id);

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
        //   3. Delete the DEK from the host keychain so the test does not
        //      pollute the user's Windows Credential Manager.
        //   4. Remove the unique temp dir.
        let _ = moss2.uninstall_keystore();
        clear_moss_keystore();
        let _ = OsSecureSecretStore.delete_secret(DEK_KEY);
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
    fn set_app_data_dir_rejects_second_call() {
        // Idempotent-once: the first call wins; the second returns Err. This
        // test sets the process-global cell (OnceLock is irreversible), but
        // the cell is inert in the test binary -- no test exercises
        // `construct_runtime` (its only reader) -- so leaving it set cannot
        // contaminate the other 218 tests. The dir is a unique temp subdir so
        // a hypothetical future reader would point at an isolated, real path.
        let dir = unique_test_dir("app_data_dir_set");
        std::fs::create_dir_all(&dir).expect("test dir should create");
        assert!(
            super::set_app_data_dir(dir.to_string_lossy().to_string()).is_ok(),
            "first set_app_data_dir call must succeed"
        );
        assert!(
            super::set_app_data_dir(dir.to_string_lossy().to_string()).is_err(),
            "second set_app_data_dir call must be rejected (idempotent-once)"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
