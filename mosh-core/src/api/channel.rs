//! Channel facade.
//!
//! Surfaces the former `channel_*` Tauri command group: join, leave, send,
//! retry_message, poll, list, attachment send/download/cancel, and the
//! send/dismiss DM-offer commands. Poll maps to a `StreamSink`-returning
//! facade function, mirroring the former Tauri event that streamed channel
//! updates.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<ChannelRuntime>>>`, the analogue of the Tauri
//! shell's `ChannelState` (managed struct + `runtime: Mutex<Option<...>>`
//! + `load_error`). `ensure_runtime()` is the analogue of
//! `ChannelState::ready` (construction) + `with_runtime` (lock + borrow).
//! Each public function calls `ensure_runtime()` and delegates, mapping
//! `ChannelRuntimeError` to a plain `String` so the bridge surfaces it as
//! a Dart exception (ADR 0010).
//!
//! SHARED RESOURCES (ADR 0016 -- shared-runtime refactor): the Moss node +
//! attachment store + persistence are borrowed from `api::shared_runtime`
//! via `ensure_shared_resources()`, exactly like the Tauri shell's
//! `ChannelState::ready(shared_node, attachment_store, persistence)` which
//! was handed the SAME `Arc<SharedMossNode>` the DM/group states got. No
//! per-facade Moss load.
//!
//! TYPES (ADR 0010 -- 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::channel_runtime::{...}`.
//! They are NOT redefined. `Result<T, String>` matches the Tauri command
//! shape exactly; this facade maps `ChannelRuntimeError` to a plain
//! `String` so the bridge surfaces it as a Dart exception.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::channel_runtime::{
    ChannelLeaveResult, ChannelListSnapshot, ChannelRuntime, ChannelRuntimeError,
    ChannelSendResult, ChannelSnapshot, JoinChannelRequest,
};
use crate::private_dm_runtime::{AttachmentSendResult, VoiceMeta};

// Mirrors the Tauri shell's `CHANNEL_UNAVAILABLE` constant so the error
// string is byte-identical across the old and new shells.
const CHANNEL_UNAVAILABLE: &str = "channel runtime unavailable";
const LOCK_POISONED: &str = "channel runtime lock poisoned";

/// Process-global singleton for the channel runtime (ADR 0016).
///
/// `Option` carries the same "ready vs missing" duality the Tauri shell's
/// `ChannelState` did: `Some` once Moss loaded, `None` if construction
/// failed (so later calls report the original error instead of retrying
/// into the same failure). The `OnceLock` guarantees a single
/// construction; the `Mutex` serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<ChannelRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call (the Tauri shell kept this in `ChannelState::load_error`).
static LOAD_ERROR: OnceLock<String> = OnceLock::new();

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: borrow the shared resources (Moss node + attachment
/// store + persistence via `api::shared_runtime`), build the channel
/// runtime off them, rehydrate saved channels from the encrypted store,
/// and store it. On every later call: just lock. Returns a guard the
/// public functions can drive the `&mut self` runtime through, or an error
/// string matching the Tauri shell's `unavailable_message` shape.
fn ensure_runtime() -> Result<MutexGuard<'static, Option<ChannelRuntime>>, String> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex.lock().map_err(|_| LOCK_POISONED.to_string())?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{CHANNEL_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| CHANNEL_UNAVAILABLE.to_string());
        return Err(message);
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
/// saved channels from the encrypted store. Mirrors the Tauri shell's
/// `ChannelState::ready` (lib.rs L139-160) including the `rehydrate()` call.
fn construct_runtime() -> Result<ChannelRuntime, ChannelRuntimeError> {
    let resources = crate::api::shared_runtime::ensure_shared_resources()
        .map_err(|error| ChannelRuntimeError::Moss(error))?;
    let mut runtime = ChannelRuntime::from_shared_node(
        resources.shared_node,
        resources.attachment_store,
        resources.persistence,
    );
    // Rehydrate saved channels from the encrypted store; with persistence
    // wired it now rebuilds joined channels + their tails instead of the
    // slice-one no-op. Matches the Tauri shell's `ChannelState::ready`
    // ordering (lib.rs L147).
    runtime.rehydrate();
    Ok(runtime)
}

/// Join a public channel (1:1 port of the `channel_join` Tauri command).
pub fn join(request: JoinChannelRequest) -> Result<ChannelSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.join(request).map_err(|error| error.to_string())
}

/// Leave a channel (1:1 port of `channel_leave`).
pub fn leave(name: String) -> Result<ChannelLeaveResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.leave(&name).map_err(|error| error.to_string())
}

/// Send a message into a channel (1:1 port of `channel_send`).
pub fn send(name: String, body: String) -> Result<ChannelSendResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.send(&name, body).map_err(|error| error.to_string())
}

/// Retry a failed channel message (1:1 port of `channel_retry_message`).
pub fn retry_message(name: String, message_id: String) -> Result<ChannelSendResult, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .retry_message(&name, &message_id)
        .map_err(|error| error.to_string())
}

/// Poll a channel for its current snapshot (1:1 port of `channel_poll`).
/// The React frontend polled on a cadence; the bridge slice will offer the
/// `StreamSink`-returning variant alongside this one-shot poll.
pub fn poll(name: String) -> Result<ChannelSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.poll(&name).map_err(|error| error.to_string())
}

/// List all joined channels and their snapshots (1:1 port of `channel_list`).
pub fn list() -> Result<ChannelListSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.list().map_err(|error| error.to_string())
}

/// Send an attachment into a channel (1:1 port of `channel_send_attachment`).
/// The bytes arrive base64-encoded (the bridge contract for all
/// send_attachment facades); decoded here before handing the raw `Vec<u8>`
/// to the runtime, matching the Tauri shell's `channel_send_attachment`
/// (lib.rs). `thumbnail_base64` is forwarded verbatim (the runtime stores
/// it as-is for the receiver's preview); `voice` is the optional `VoiceMeta`
/// for voice clips (None for plain files). Returns the new attachment's id
/// + content hash so the bridge caller can invalidate its snapshot.
pub fn send_attachment(
    name: String,
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
        .send_attachment(&name, file_name, mime, bytes, thumbnail_base64, voice)
        .map_err(|error| error.to_string())
}

/// Download a channel attachment (1:1 port of `channel_download_attachment`).
pub fn download_attachment(name: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .download_attachment(&name, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Cancel a channel attachment transfer (1:1 port of `channel_cancel_attachment`).
pub fn cancel_attachment(name: String, attachment_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .cancel_attachment(&name, &attachment_id)
        .map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one channel member
/// (1:1 port of `channel_send_dm_offer`).
pub fn send_dm_offer(
    name: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .send_dm_offer(&name, target_fingerprint, invite_uri)
        .map_err(|error| error.to_string())
}

/// Dismiss a channel DM offer (1:1 port of `channel_dismiss_dm_offer`).
pub fn dismiss_dm_offer(name: String, offer_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&name, &offer_id)
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
