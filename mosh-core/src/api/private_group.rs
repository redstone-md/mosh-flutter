//! Private group bridge operations. Shared resources and runtime ownership live in
//! `shared_runtime` and `runtime_owner` (ADRs 0016 and 0024).

use std::sync::MutexGuard;

use super::runtime_owner::RuntimeOwner;

use crate::api::conversation_bridge::ConversationBridgeError;
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupListSnapshot, GroupSnapshot, JoinGroupRequest,
    PrivateGroupError, PrivateGroupRuntime,
};

static RUNTIME: RuntimeOwner<PrivateGroupRuntime> = RuntimeOwner::new("private group");
#[path = "private_group_service.rs"]
mod service;

pub(crate) fn ensure_runtime(
) -> Result<MutexGuard<'static, PrivateGroupRuntime>, ConversationBridgeError> {
    RUNTIME.lock(construct_runtime)
}

fn construct_runtime() -> Result<PrivateGroupRuntime, PrivateGroupError> {
    let resources =
        crate::api::shared_runtime::ensure_shared_resources().map_err(PrivateGroupError::Moss)?;
    let mut runtime = PrivateGroupRuntime::from_shared_node(
        resources.shared_node,
        resources.attachment_store,
        resources.persistence,
    );
    // Rehydrate saved groups from the encrypted store; with persistence
    // wired it rebuilds joined groups + their tails + MLS state.
    runtime.rehydrate();
    service::start().map_err(PrivateGroupError::Moss)?;
    Ok(runtime)
}

/// Create a private MLS group.
pub fn create_group(request: CreateGroupRequest) -> Result<GroupCreated, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .create_group(request)
        .map_err(ConversationBridgeError::from)
}

/// Join a private group from an invite URI.
pub fn join_group(request: JoinGroupRequest) -> Result<GroupSnapshot, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .join_group(request)
        .map_err(ConversationBridgeError::from)
}

/// Poll a private group for its current snapshot.
pub fn poll(group_id: String) -> Result<GroupSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.poll(&group_id).map_err(|error| error.to_string())
}

/// List all private groups and their snapshots.
pub fn list() -> Result<GroupListSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.list().map_err(|error| error.to_string())
}

/// Publish a private-DM invitation to one group member.
pub fn send_dm_offer(
    group_id: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), ConversationBridgeError> {
    let invite_uri = super::private_dm::ensure_runtime()?
        .authenticated_owned_invite(&invite_uri, &target_fingerprint)?;
    let mut runtime = ensure_runtime()?;
    runtime
        .send_dm_offer(&group_id, target_fingerprint, invite_uri)
        .map_err(ConversationBridgeError::from)
}

/// Dismiss a private-group DM offer.
pub fn dismiss_dm_offer(group_id: String, offer_id: String) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .dismiss_dm_offer(&group_id, &offer_id)
        .map_err(ConversationBridgeError::from)
}

/// Inspect only an already-created runtime; background Stop must not open rooms.
pub(crate) fn background_work() -> Result<(u32, u32), String> {
    let Some(runtime) = RUNTIME.initialized() else {
        return Ok((0, 0));
    };
    runtime
        .lock()
        .map_err(|_| "private group runtime lock poisoned".to_string())?
        .background_work()
        .map_err(|error| error.to_string())
}

/// Hydrate retained joined groups after native key startup, without UI polling.
pub(crate) fn ensure_background_runtime() -> Result<(), String> {
    drop(ensure_runtime().map_err(|error| error.to_string())?);
    Ok(())
}
