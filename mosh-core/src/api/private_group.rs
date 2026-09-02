//! Private-group facade: the group-specific bridge operations.
//!
//! Create, join, poll, list, and the send/dismiss DM-offer commands. The
//! actions every conversation kind shares — send, retry, attachment
//! send/download/cancel, leave — live once in `api::conversation` (ADR
//! 0024) and borrow this facade's runtime lock through `ensure_runtime()`.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<PrivateGroupRuntime>>>`, the analogue of the
//! Tauri shell's `PrivateGroupState` (managed struct +
//! `runtime: Mutex<Option<...>>` + `load_error`). `ensure_runtime()` is
//! the analogue of `PrivateGroupState::ready` (construction) +
//! `with_runtime` (lock + borrow). Each public function calls
//! `ensure_runtime()` and delegates. The actions (create, join, DM offers)
//! return the typed `ConversationBridgeError` (ADR 0024); the two reads
//! keep the plain `String` shape (ADR 0010).
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

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupListSnapshot, GroupSnapshot, JoinGroupRequest,
    PrivateGroupError, PrivateGroupRuntime,
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
/// functions can drive the `&mut self` runtime through, or an `Unavailable`
/// bridge error carrying the Tauri shell's `unavailable_message` text.
pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, Option<PrivateGroupRuntime>>, ConversationBridgeError> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex
        .lock()
        .map_err(|_| ConversationBridgeError::unavailable(LOCK_POISONED))?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{PRIVATE_GROUP_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| PRIVATE_GROUP_UNAVAILABLE.to_string());
        return Err(ConversationBridgeError::unavailable(message));
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
    let resources =
        crate::api::shared_runtime::ensure_shared_resources().map_err(PrivateGroupError::Moss)?;
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
pub fn create_group(request: CreateGroupRequest) -> Result<GroupCreated, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .create_group(request)
        .map_err(ConversationBridgeError::from)
}

/// Join a private group from an invite URI (1:1 port of `private_group_join`).
pub fn join_group(request: JoinGroupRequest) -> Result<GroupSnapshot, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .join_group(request)
        .map_err(ConversationBridgeError::from)
}

/// Poll a private group for its current snapshot (1:1 port of
/// `private_group_poll`).
pub fn poll(group_id: String) -> Result<GroupSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.poll(&group_id).map_err(|error| error.to_string())
}

/// List all private groups and their snapshots (1:1 port of
/// `private_group_list`).
pub fn list() -> Result<GroupListSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list().map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one group member (1:1 port of
/// `private_group_send_dm_offer`).
pub fn send_dm_offer(
    group_id: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_dm_offer(&group_id, target_fingerprint, invite_uri)
        .map_err(ConversationBridgeError::from)
}

/// Dismiss a private-group DM offer (1:1 port of
/// `private_group_dismiss_dm_offer`).
pub fn dismiss_dm_offer(group_id: String, offer_id: String) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&group_id, &offer_id)
        .map_err(ConversationBridgeError::from)
}
