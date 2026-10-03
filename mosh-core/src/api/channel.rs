//! Channel bridge operations. Shared resources and runtime ownership live in
//! `shared_runtime` and `runtime_owner` (ADRs 0016 and 0024).

use std::sync::MutexGuard;

use super::runtime_owner::RuntimeOwner;

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::channel_runtime::{
    ChannelListSnapshot, ChannelRuntime, ChannelRuntimeError, ChannelSnapshot, JoinChannelRequest,
};

static RUNTIME: RuntimeOwner<ChannelRuntime> = RuntimeOwner::new("channel");

pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, ChannelRuntime>, ConversationBridgeError> {
    RUNTIME.lock(construct_runtime)
}

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
    let mut runtime = ensure_runtime()?;
    runtime.join(request).map_err(ConversationBridgeError::from)
}

/// Poll a channel for its current snapshot. The Dart side polls on a cadence.
pub fn poll(name: String) -> Result<ChannelSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.poll(&name).map_err(|error| error.to_string())
}

/// List all joined channels and their snapshots.
pub fn list() -> Result<ChannelListSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.list().map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one channel member.
pub fn send_dm_offer(
    name: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .send_dm_offer(&name, target_fingerprint, invite_uri)
        .map_err(ConversationBridgeError::from)
}

/// Dismiss a channel DM offer.
pub fn dismiss_dm_offer(name: String, offer_id: String) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .dismiss_dm_offer(&name, &offer_id)
        .map_err(ConversationBridgeError::from)
}
