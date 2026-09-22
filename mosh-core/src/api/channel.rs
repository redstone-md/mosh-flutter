//! Channel facade: the channel-specific bridge operations.
//!
//! Join, poll, list, and the send/dismiss DM-offer commands. The actions
//! every conversation kind shares — send, retry, attachment
//! send/download/cancel, leave — live once in `api::conversation` (ADR
//! 0024) and borrow this facade's runtime lock through `ensure_runtime()`.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<ChannelRuntime>>>` plus a cached `load_error`.
//! `ensure_runtime()` constructs the singleton on first call, then locks
//! and borrows it. Each public function calls `ensure_runtime()` and
//! delegates. The
//! actions (join, DM offers) return the typed `ConversationBridgeError`
//! (ADR 0024); the two reads keep the plain `String` shape (ADR 0010).
//!
//! SHARED RESOURCES (ADR 0016 -- shared-runtime refactor): the Moss node +
//! attachment store + persistence are borrowed from `api::shared_runtime`
//! via `ensure_shared_resources()`: the same `Arc<SharedMossNode>` the
//! DM/group facades get. No per-facade Moss load.
//!
//! TYPES (ADR 0010 -- 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::channel_runtime::{...}`.
//! They are NOT redefined.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::channel_runtime::{
    ChannelListSnapshot, ChannelRuntime, ChannelRuntimeError, ChannelSnapshot, JoinChannelRequest,
};

const CHANNEL_UNAVAILABLE: &str = "channel runtime unavailable";
const LOCK_POISONED: &str = "channel runtime lock poisoned";

/// Process-global singleton for the channel runtime (ADR 0016).
///
/// `Option` carries the "ready vs missing" duality: `Some` once Moss
/// loaded, `None` if construction failed (so later calls report the
/// original error instead of retrying into the same failure). The `OnceLock` guarantees a single
/// construction; the `Mutex` serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<ChannelRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call.
static LOAD_ERROR: OnceLock<String> = OnceLock::new();

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: borrow the shared resources (Moss node + attachment
/// store + persistence via `api::shared_runtime`), build the channel
/// runtime off them, rehydrate saved channels from the encrypted store,
/// and store it. On every later call: just lock. Returns a guard the
/// public functions can drive the `&mut self` runtime through, or an
/// `Unavailable` bridge error.
pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, Option<ChannelRuntime>>, ConversationBridgeError> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex
        .lock()
        .map_err(|_| ConversationBridgeError::unavailable(LOCK_POISONED))?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{CHANNEL_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| CHANNEL_UNAVAILABLE.to_string());
        return Err(ConversationBridgeError::unavailable(message));
    }
    Ok(guard)
}

/// Build the singleton value once. Returns `Some(runtime)` on success, or
/// `None` + caches the cause in `LOAD_ERROR` on failure. Split out from
/// `ensure_runtime` to keep that function's nesting shallow.
fn build_runtime() -> Option<ChannelRuntime> {
    match construct_runtime() {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            let _ = LOAD_ERROR.set(error.to_string());
            None
        }
    }
}

/// The channel-runtime construction recipe: borrow the shared resources
/// (Moss node + attachment store + persistence) from `api::shared_runtime`,
/// build a `ChannelRuntime::from_shared_node` off them, then rehydrate
/// saved channels from the encrypted store.
fn construct_runtime() -> Result<ChannelRuntime, ChannelRuntimeError> {
    let resources =
        crate::api::shared_runtime::ensure_shared_resources().map_err(ChannelRuntimeError::Moss)?;
    let mut runtime = ChannelRuntime::from_shared_node(
        resources.shared_node,
        resources.attachment_store,
        resources.persistence,
    );
    // Rehydrate saved channels from the encrypted store; with persistence
    // wired it rebuilds joined channels + their tails.
    runtime.rehydrate();
    Ok(runtime)
}

/// Join a public channel.
pub fn join(request: JoinChannelRequest) -> Result<ChannelSnapshot, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.join(request).map_err(ConversationBridgeError::from)
}

/// Poll a channel for its current snapshot. The Dart side polls on a cadence.
pub fn poll(name: String) -> Result<ChannelSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.poll(&name).map_err(|error| error.to_string())
}

/// List all joined channels and their snapshots.
pub fn list() -> Result<ChannelListSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list().map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one channel member.
pub fn send_dm_offer(
    name: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_dm_offer(&name, target_fingerprint, invite_uri)
        .map_err(ConversationBridgeError::from)
}

/// Dismiss a channel DM offer.
pub fn dismiss_dm_offer(name: String, offer_id: String) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&name, &offer_id)
        .map_err(ConversationBridgeError::from)
}
