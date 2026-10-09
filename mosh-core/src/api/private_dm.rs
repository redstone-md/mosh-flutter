//! Private dm bridge operations. Shared resources and runtime ownership live in
//! `shared_runtime` and `runtime_owner` (ADRs 0016 and 0024).

use std::sync::{Arc, MutexGuard, OnceLock};

use super::runtime_owner::RuntimeOwner;
use std::time::Duration;

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::private_dm_runtime::{
    AcceptInviteRequest, CallMedia, CallStarted, InviteCreated, PrivateDmRuntime,
    PrivateDmRuntimeError, SessionListSnapshot, SessionSnapshot, StartSessionRequest,
};

static RUNTIME: RuntimeOwner<PrivateDmRuntime> = RuntimeOwner::new("private DM");

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

pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, PrivateDmRuntime>, ConversationBridgeError> {
    RUNTIME.lock(construct_runtime)
}

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
    start_service_thread();
    Ok(runtime)
}

/// Create a private-DM invite. The inviter publishes a KeyPackage and an invite URI.
pub fn create_invite(
    request: StartSessionRequest,
) -> Result<InviteCreated, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .create_invite(request)
        .map_err(ConversationBridgeError::from)
}

/// Save an invitation without adding its conversation to the recent-chat list.
pub fn create_pending_invite(
    request: StartSessionRequest,
) -> Result<InviteCreated, ConversationBridgeError> {
    ensure_runtime()?
        .create_pending_invite(request)
        .map_err(ConversationBridgeError::from)
}

/// Saved invitations remain available after navigation and restart.
pub fn list_pending_invites() -> Result<Vec<InviteCreated>, ConversationBridgeError> {
    ensure_runtime()?
        .list_pending_invites()
        .map_err(ConversationBridgeError::from)
}

/// Replace only this unconsumed invitation while preserving its conversation.
pub fn replace_invite(session_id: String) -> Result<InviteCreated, ConversationBridgeError> {
    ensure_runtime()?
        .replace_invite(&session_id)
        .map_err(ConversationBridgeError::from)
}

/// Durably add a saved invitation's conversation to the recent-chat list.
pub fn open_session(session_id: String) -> Result<SessionSnapshot, ConversationBridgeError> {
    ensure_runtime()?
        .open_session(&session_id)
        .map_err(ConversationBridgeError::from)
}

/// Accept a private-DM invite. The
/// joiner parses the invite URI and processes the inviter's Welcome.
pub fn accept_invite(
    request: AcceptInviteRequest,
) -> Result<SessionSnapshot, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .accept_invite(request)
        .map_err(ConversationBridgeError::from)
}

/// Poll a session for its current snapshot. The Dart side calls this
/// on a poll cadence; no push, no StreamSink.
pub fn poll_session(session_id: String) -> Result<SessionSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime
        .poll_session(&session_id)
        .map_err(|error| error.to_string())
}

/// List all sessions and their snapshots.
pub fn list_sessions() -> Result<SessionListSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.list_sessions().map_err(|error| error.to_string())
}

/// Start a voice call in a DM session. Mints the call id + the
/// symmetric call key + nonce prefix, publishes a CallOffer to the peer
/// over the session MLS channel, and moves the session into the
/// outgoing-ringing state (SessionSnapshot.outgoing_call). The bridge
/// returns CallStarted so the caller can begin capturing + sealing frames.
pub fn call_start(session_id: String) -> Result<CallStarted, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .call_start(&session_id)
        .map_err(ConversationBridgeError::from)
}

/// Accept an incoming voice call.
/// Requests selection with an authenticated answer. Media remains pending until
/// the caller confirms that this installation is the selected receiver.
pub fn call_accept(session_id: String, call_id: String) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
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
    let mut runtime = ensure_runtime()?;
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
    let mut runtime = ensure_runtime()?;
    runtime
        .call_end(&session_id, &call_id, &reason)
        .map_err(ConversationBridgeError::from)
}

/// How often the service thread runs the DM protocol. Twice the old UI poll
/// rate, so a keepalive or a handshake step never waits long for a tick.
const SERVICE_INTERVAL: Duration = Duration::from_millis(500);

/// Runs the DM protocol on its own thread for the life of the process, so it
/// no longer stops when the UI stops polling. The runtime is not built yet
/// when this starts (it is called from inside the `RUNTIME` init), so each
/// pass looks it up; a poisoned lock ends the thread, since every later
/// call reports the runtime unavailable anyway.
fn start_service_thread() {
    let spawned = std::thread::Builder::new()
        .name("mosh-dm-service".to_string())
        .spawn(|| loop {
            std::thread::sleep(SERVICE_INTERVAL);
            let Some(mutex) = RUNTIME.initialized() else {
                continue;
            };
            let Ok(mut guard) = mutex.lock() else {
                return;
            };
            guard.service();
        });
    if let Err(error) = spawned {
        dlog::write(
            LogLevel::Error,
            kinds::SERVICE,
            "",
            &format!("could not start the DM service thread: {error}"),
        );
    }
}

/// The call media hub, cached after the first call so the 20 ms audio loop
/// never takes the runtime lock again.
fn call_media() -> Result<Arc<CallMedia>, String> {
    static CALL_MEDIA: OnceLock<Arc<CallMedia>> = OnceLock::new();
    if let Some(media) = CALL_MEDIA.get() {
        return Ok(Arc::clone(media));
    }
    let guard = ensure_runtime().map_err(|error| error.to_string())?;
    let media = guard.call_media();
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
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime
        .set_read_receipts_enabled(enabled)
        .map_err(|error| error.to_string())
}

#[cfg(test)]
#[path = "private_dm_tests.rs"]
mod tests;
