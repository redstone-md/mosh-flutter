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
//! PERSISTENCE: the Tauri shell built `Persistence::open(app_data_dir)` in
//! `setup()` and handed the resulting `Arc<Persistence>` to the runtime so
//! conversations survive restart. The api facade owns no DB path yet (the
//! bridge does not pass one in slice one), so the singleton is initialized
//! with `persistence: None`. `rehydrate()` is still called (it is a no-op
//! without a store) so the wiring is correct the moment a path arrives in a
//! later slice. Persistence wiring is a later-slice deliverable, not a hack.
//!
//! TESTING: `ensure_runtime()` calls `MossFfiRuntime::load_default()`, which
//! loads the Moss shared library. There is no way to exercise ANY of the
//! six public functions without triggering that load, so a unit test here
//! would require the Moss lib to be present and would fail in CI without
//! it. `api::private_dm` is therefore integration-tested in S2/S5 (live
//! Moss), not unit-tested here — per the task brief point 6.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::attachment_store::AttachmentStore;
use crate::moss_ffi::MossFfiRuntime;
use crate::private_dm_runtime::{
    AcceptInviteRequest, CloseSessionResult, InviteCreated, PrivateDmRuntime,
    PrivateDmRuntimeError, SendMessageResult, SessionListSnapshot, SessionSnapshot,
    StartSessionRequest,
};
use crate::shared_node::SharedMossNode;

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

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: load Moss, build the attachment store, construct the
/// runtime, rehydrate saved conversations, and store it. On every later
/// call: just lock. Returns a guard the public functions can drive the
/// `&mut self` runtime through, or an error string matching the Tauri
/// shell's `unavailable_message` shape.
fn ensure_runtime() -> Result<MutexGuard<'static, Option<PrivateDmRuntime>>, String> {
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
/// `ensure_runtime` to keep that function's nesting shallow and its body
/// under 50 LOC (AGENTS.md function_max_loc).
fn build_runtime() -> Option<PrivateDmRuntime> {
    match construct_runtime() {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            let _ = LOAD_ERROR.set(error.to_string());
            None
        }
    }
}

/// The construction recipe — a verbatim port of the Tauri shell's
/// `PrivateDmState::ready`, minus the keystore/persistence wiring that
/// needs a DB path the api facade does not own yet (see module doc).
fn construct_runtime() -> Result<PrivateDmRuntime, PrivateDmRuntimeError> {
    // `load_default` internally calls
    // `MossDynamicRuntime::from_default_candidates` (same path the Tauri
    // shell's `tauri_moss::load_moss_runtime_from_app_handle` took). Failure
    // here is the "missing moss.dll" case the Tauri shell surfaced as
    // `PrivateDmState::missing(message)`.
    let moss = MossFfiRuntime::load_default()
        .map_err(|error| PrivateDmRuntimeError::Moss(error.to_string()))?;
    // One holder for the whole process: DMs, channels, groups and orgs share
    // a single Moss node (see `shared_node`). The api facade owns its own
    // holder today; when other api slices land, they should take a
    // reference to THIS shared node rather than minting their own.
    let shared_node = SharedMossNode::new(std::sync::Arc::new(moss));
    // The Tauri shell preferred `app_data_dir` then fell back to temp. The
    // api facade has no app handle, so it uses a `mosh` dir under the temp
    // dir — the same fallback the Tauri shell used when app_data_dir failed.
    let attachment_store = std::sync::Arc::new(
        AttachmentStore::new(std::env::temp_dir().join("mosh"))
            .map_err(|error| PrivateDmRuntimeError::Moss(error.to_string()))?,
    );
    // persistence: None for slice one — see module doc.
    let mut runtime = PrivateDmRuntime::from_shared_node(shared_node, attachment_store, None);
    // The Tauri shell calls `rehydrate()` after construction; it is a no-op
    // without a persistence store, so this is correct today and stays
    // correct the moment a later slice wires a DB path.
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

// No unit tests: every public function routes through `ensure_runtime`,
// which calls `MossFfiRuntime::load_default` and therefore loads the Moss
// shared library. There is no way to exercise the facade without that load,
// so a test here would fail in CI without the lib present. `api::private_dm`
// is integration-tested in S2/S5 (live Moss), not unit-tested — see module doc.
