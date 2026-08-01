//! Private-group facade.
//!
//! Surfaces the former `private_group_*` Tauri command group: create, join,
//! send, retry_message, poll, list, close, attachment send/download/cancel,
//! and the send/dismiss DM-offer commands. Poll maps to a
//! `StreamSink`-returning facade function, mirroring the former Tauri event
//! that streamed private-group updates.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<PrivateGroupRuntime>>>`, the analogue of the
//! Tauri shell's `PrivateGroupState` (managed struct +
//! `runtime: Mutex<Option<...>>` + `load_error`). `ensure_runtime()` is
//! the analogue of `PrivateGroupState::ready` (construction) +
//! `with_runtime` (lock + borrow). Each public function calls
//! `ensure_runtime()` and delegates, mapping `PrivateGroupError` to a
//! plain `String` so the bridge surfaces it as a Dart exception (ADR 0010).
//!
//! SHARED RESOURCES (ADR 0016 -- shared-runtime refactor): the Moss node +
//! attachment store + persistence are borrowed from `api::shared_runtime`
//! via `ensure_shared_resources()`, exactly like the Tauri shell's
//! `PrivateGroupState::ready(shared_node, attachment_store, persistence)`
//! which was handed the SAME `Arc<SharedMossNode>` the DM/channel states
//! got. No per-facade Moss load.
//!
//! TYPES (ADR 0010 -- 1:1 mapping, DRY): the request/return types are the
//! runtime's own, re-exported here via
//! `use crate::private_group_runtime::{...}`. They are NOT redefined.
//! `Result<T, String>` matches the Tauri command shape exactly; this
//! facade maps `PrivateGroupError` to a plain `String` so the bridge
//! surfaces it as a Dart exception.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::private_dm_runtime::{AttachmentSendResult, VoiceMeta};
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupListSnapshot, GroupLeaveResult, GroupSendResult,
    GroupSnapshot, JoinGroupRequest, PrivateGroupError, PrivateGroupRuntime,
};

// Mirrors the Tauri shell's `PRIVATE_GROUP_UNAVAILABLE` constant so the
// error string is byte-identical across the old and new shells.
const PRIVATE_GROUP_UNAVAILABLE: &str = "private group runtime unavailable";
const LOCK_POISONED: &str = "private group runtime lock poisoned";

/// Process-global singleton for the private-group runtime (ADR 0016).
///
/// `Option` carries the same "ready vs missing" duality the Tauri shell's
/// `PrivateGroupState` did: `Some` once Moss loaded, `None` if construction
/// failed (so later calls report the original error instead of retrying
/// into the same failure). The `OnceLock` guarantees a single
/// construction; the `Mutex` serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<PrivateGroupRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call (the Tauri shell kept this in
/// `PrivateGroupState::load_error`).
static LOAD_ERROR: OnceLock<String> = OnceLock::new();

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: borrow the shared resources (Moss node + attachment
/// store + persistence via `api::shared_runtime`), build the group
/// runtime off them, rehydrate saved groups from the encrypted store, and
/// store it. On every later call: just lock. Returns a guard the public
/// functions can drive the `&mut self` runtime through, or an error string
/// matching the Tauri shell's `unavailable_message` shape.
fn ensure_runtime() -> Result<MutexGuard<'static, Option<PrivateGroupRuntime>>, String> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex.lock().map_err(|_| LOCK_POISONED.to_string())?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{PRIVATE_GROUP_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| PRIVATE_GROUP_UNAVAILABLE.to_string());
        return Err(message);
    }
    Ok(guard)
}

/// Build the singleton value once. Returns `Some(runtime)` on success, or
/// `None` + caches the cause in `LOAD_ERROR` on failure. Split out from
/// `ensure_runtime` to keep that function's nesting shallow.
fn build_runtime() -> Option<PrivateGroupRuntime> {
    match construct_runtime() {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            let _ = LOAD_ERROR.set(error.to_string());
            None
        }
    }
}

/// The group-runtime construction recipe: borrow the shared resources (Moss
/// node + attachment store + persistence) from `api::shared_runtime`,
/// build a `PrivateGroupRuntime::from_shared_node` off them, then rehydrate
/// saved groups from the encrypted store. Mirrors the Tauri shell's
/// `PrivateGroupState::ready` (lib.rs L203-224) including the `rehydrate()`
/// call.
fn construct_runtime() -> Result<PrivateGroupRuntime, PrivateGroupError> {
    let resources = crate::api::shared_runtime::ensure_shared_resources()
        .map_err(|error| PrivateGroupError::Moss(error))?;
    let mut runtime = PrivateGroupRuntime::from_shared_node(
        resources.shared_node,
        resources.attachment_store,
        resources.persistence,
    );
    // Rehydrate saved groups from the encrypted store; with persistence
    // wired it now rebuilds joined groups + their tails + MLS state
    // instead of the slice-one no-op. Matches the Tauri shell's
    // `PrivateGroupState::ready` ordering (lib.rs L211).
    runtime.rehydrate();
    Ok(runtime)
}

/// Create a private MLS group (1:1 port of `private_group_create`).
pub fn create_group(request: CreateGroupRequest) -> Result<GroupCreated, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .create_group(request)
        .map_err(|error| error.to_string())
}

/// Join a private group from an invite URI (1:1 port of `private_group_join`).
pub fn join_group(request: JoinGroupRequest) -> Result<GroupSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .join_group(request)
        .map_err(|error| error.to_string())
}

/// Send a message into a private group (1:1 port of `private_group_send`).
pub fn send(group_id: String, body: String) -> Result<GroupSendResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send(&group_id, body)
        .map_err(|error| error.to_string())
}

/// Retry a failed private-group message (1:1 port of
/// `private_group_retry_message`).
pub fn retry_message(group_id: String, message_id: String) -> Result<GroupSendResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .retry_message(&group_id, &message_id)
        .map_err(|error| error.to_string())
}

/// Poll a private group for its current snapshot (1:1 port of
/// `private_group_poll`).
pub fn poll(group_id: String) -> Result<GroupSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .poll(&group_id)
        .map_err(|error| error.to_string())
}

/// List all private groups and their snapshots (1:1 port of
/// `private_group_list`).
pub fn list() -> Result<GroupListSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list().map_err(|error| error.to_string())
}

/// Close and tear down a private group (1:1 port of `private_group_close`).
pub fn close(group_id: String) -> Result<GroupLeaveResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .close(&group_id)
        .map_err(|error| error.to_string())
}

/// Send an attachment into a private group (1:1 port of
/// `private_group_send_attachment`). The bytes arrive base64-encoded (the
/// bridge contract for all send_attachment facades); decoded here before
/// handing the raw `Vec<u8>` to the runtime, matching the Tauri shell's
/// `private_group_send_attachment` (lib.rs). `thumbnail_base64` is
/// forwarded verbatim (the runtime stores it as-is for the receiver's
/// preview); `voice` is the optional `VoiceMeta` for voice clips (None for
/// plain files). Returns the new attachment's id + content hash so the
/// bridge caller can invalidate its snapshot.
pub fn send_attachment(
    group_id: String,
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
        .send_attachment(&group_id, file_name, mime, bytes, thumbnail_base64, voice)
        .map_err(|error| error.to_string())
}

/// Download a private-group attachment (1:1 port of
/// `private_group_download_attachment`).
pub fn download_attachment(group_id: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .download_attachment(&group_id, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Cancel a private-group attachment transfer (1:1 port of
/// `private_group_cancel_attachment`).
pub fn cancel_attachment(group_id: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .cancel_attachment(&group_id, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one group member (1:1 port of
/// `private_group_send_dm_offer`).
pub fn send_dm_offer(
    group_id: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_dm_offer(&group_id, target_fingerprint, invite_uri)
        .map_err(|error| error.to_string())
}

/// Dismiss a private-group DM offer (1:1 port of
/// `private_group_dismiss_dm_offer`).
pub fn dismiss_dm_offer(group_id: String, offer_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&group_id, &offer_id)
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