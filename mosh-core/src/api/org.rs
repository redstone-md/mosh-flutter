//! Org bridge operations. Shared resources and runtime ownership live in
//! `shared_runtime` and `runtime_owner` (ADRs 0016 and 0024).
//! Paired acceptance and creation lock Org before DM/group. Their loaders and
//! polling use shared resources and persisted rosters without reacquiring Org.

use std::sync::MutexGuard;

use super::runtime_owner::RuntimeOwner;

use crate::api::conversation_bridge::{ConversationBridgeError, ConversationBridgeErrorKind};
use crate::org_runtime::{JoinOrgRequest, OrgError, OrgRuntime, OrgSnapshot};
use crate::private_dm_runtime::{
    AcceptInviteRequest, InviteCreated, SessionSnapshot, StartSessionRequest,
};
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupSnapshot, JoinGroupRequest,
};

static RUNTIME: RuntimeOwner<OrgRuntime> = RuntimeOwner::new("org");

#[path = "org_workflows.rs"]
pub(crate) mod workflows;

#[cfg(test)]
#[path = "org_workflow_tests.rs"]
pub(crate) mod workflow_tests;

const GROUP_WITHOUT_INVITE: &str = "group has no invite URI";

fn ensure_runtime() -> Result<MutexGuard<'static, OrgRuntime>, ConversationBridgeError> {
    RUNTIME.lock(construct_runtime)
}

fn construct_runtime() -> Result<OrgRuntime, OrgError> {
    let resources =
        crate::api::shared_runtime::ensure_shared_resources().map_err(OrgError::Moss)?;
    let mut runtime = OrgRuntime::from_shared_node(resources.shared_node, resources.persistence);
    // Rehydrate saved orgs from the encrypted store; with persistence wired
    // it rebuilds joined orgs + their rosters.
    runtime.rehydrate();
    Ok(runtime)
}

/// Join an org from a `mosh://org` bundle URI. Delegates to `OrgRuntime::join_org`.
pub fn join_org(request: JoinOrgRequest) -> Result<OrgSnapshot, ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .join_org(request)
        .map_err(ConversationBridgeError::from)
}

/// Leave an org and close its bound groups. This function
/// drives both the org and group singletons from one place.
pub fn leave_org(org_pubkey: String) -> Result<(), ConversationBridgeError> {
    // Drop the org from the org runtime; close its bound private groups so
    // they do not linger frozen. The group
    // runtime reconciles bound groups via close_org_groups; revocation
    // needs no extra wiring here (the group runtime reconciles against the
    // persisted roster on its own drain cadence).
    {
        let mut runtime = ensure_runtime()?;
        runtime.leave_org(&org_pubkey)?;
    }
    {
        let mut runtime = crate::api::private_group::ensure_runtime()?;
        runtime.close_org_groups(&org_pubkey);
    }
    Ok(())
}

/// List all joined orgs and their snapshots. The runtime's `list` returns a
/// `Vec<OrgSnapshot>` directly (no Result), so the facade wraps it in `Ok`
/// for the bridge's `Result<Vec<OrgSnapshot>, String>` shape.
pub fn list() -> Result<Vec<OrgSnapshot>, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    Ok(runtime.list())
}

/// Poll an org for its current snapshot. Delegates to `OrgRuntime::poll`.
pub fn poll(org_pubkey: String) -> Result<OrgSnapshot, String> {
    let mut runtime = ensure_runtime().map_err(|error| error.to_string())?;
    runtime.poll(&org_pubkey).map_err(|error| error.to_string())
}

/// Send a private-DM invitation to one org member. Mints the invite via
/// the private-DM runtime and
/// records the offer in the org runtime.
pub fn send_dm_offer(
    org_pubkey: String,
    target_peer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<InviteCreated, ConversationBridgeError> {
    // Mint the invite via the private-DM runtime, then record + link it in
    // the org runtime. On an org-side failure
    // drop the orphan local invite so it does not linger as a dead "waiting"
    // session.
    let invite = {
        let mut runtime = crate::api::private_dm::ensure_runtime()?;
        runtime.create_invite(StartSessionRequest {
            display_name,
            listen_port,
            static_peer,
        })?
    };
    let offered = {
        let mut runtime = ensure_runtime()?;
        runtime.send_dm_offer(&org_pubkey, &target_peer_id, &invite.invite_uri)?;
        runtime
            .link_dm(&org_pubkey, &target_peer_id, &invite.session_id)
            .map_err(ConversationBridgeError::from)
    };
    if let Err(error) = offered {
        // The offer never reached the mesh: drop the orphan local invite.
        let mut runtime = crate::api::private_dm::ensure_runtime()?;
        let _ = runtime.close_session(&invite.session_id);
        return Err(error);
    }
    Ok(invite)
}

/// Accept an org-carried DM offer.
/// Accepts the invite via the private-DM runtime and clears the offer in the
/// org runtime.
pub fn accept_dm_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<SessionSnapshot, ConversationBridgeError> {
    let mut org = ensure_runtime()?;
    let offer = org.peek_dm_offer(&org_pubkey, &offer_id)?;
    let mut dm = crate::api::private_dm::ensure_runtime()?;
    workflows::accept_and_link_dm(
        &mut org,
        &mut dm,
        &org_pubkey,
        &offer_id,
        AcceptInviteRequest {
            invite_uri: offer.invite_uri,
            display_name,
            listen_port,
            static_peer,
        },
    )
}

/// Dismiss an org DM offer. Delegates to
/// `OrgRuntime::dismiss_dm_offer`.
pub fn dismiss_dm_offer(
    org_pubkey: String,
    offer_id: String,
) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .dismiss_dm_offer(&org_pubkey, &offer_id)
        .map_err(ConversationBridgeError::from)
}

/// Create an org-bound private group.
/// Creates the group via the private-group runtime and records the binding in
/// the org runtime.
pub fn create_group(
    org_pubkey: String,
    label: Option<String>,
    member_peer_ids: Vec<String>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupCreated, ConversationBridgeError> {
    let mut org = ensure_runtime()?;
    let mut groups = crate::api::private_group::ensure_runtime()?;
    workflows::create_and_offer_group(
        &mut org,
        &mut groups,
        &org_pubkey,
        &member_peer_ids,
        CreateGroupRequest {
            label,
            display_name,
            listen_port,
            static_peer,
            org_pubkey: Some(org_pubkey.clone()),
        },
    )
}

/// Accept an org-carried group offer.
/// Joins the group via the private-group runtime and clears the offer in the
/// org runtime.
pub fn accept_group_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupSnapshot, ConversationBridgeError> {
    let mut org = ensure_runtime()?;
    let offer = org.peek_group_offer(&org_pubkey, &offer_id)?;
    let mut groups = crate::api::private_group::ensure_runtime()?;
    workflows::accept_and_join_group(
        &mut org,
        &mut groups,
        &org_pubkey,
        &offer_id,
        JoinGroupRequest {
            invite_uri: offer.group_invite_uri,
            display_name,
            listen_port,
            static_peer,
            org_pubkey: Some(org_pubkey.clone()),
        },
    )
}

/// Dismiss an org group offer. Delegates to
/// `OrgRuntime::dismiss_group_offer`.
pub fn dismiss_group_offer(
    org_pubkey: String,
    offer_id: String,
) -> Result<(), ConversationBridgeError> {
    let mut runtime = ensure_runtime()?;
    runtime
        .dismiss_group_offer(&org_pubkey, &offer_id)
        .map_err(ConversationBridgeError::from)
}

/// One-click invite the roster members not yet in a group. Re-offers the group's invite URI to each
/// listed peer via the org runtime's group-offer path.
pub fn group_invite_members(
    org_pubkey: String,
    group_id: String,
    member_peer_ids: Vec<String>,
) -> Result<(), ConversationBridgeError> {
    // The "+N roster members not in group" one-click add (spec §5): poll the
    // group for its invite URI + label, then re-offer the invite to each
    // listed roster member over org-control.
    let (invite_uri, label) = {
        let mut runtime = crate::api::private_group::ensure_runtime()?;
        let snapshot = runtime.poll(&group_id)?;
        let uri = snapshot.invite_uri.ok_or_else(|| {
            ConversationBridgeError::new(
                ConversationBridgeErrorKind::Internal,
                format!("{GROUP_WITHOUT_INVITE}: {group_id}"),
            )
        })?;
        (uri, snapshot.label)
    };
    {
        let mut runtime = ensure_runtime()?;
        for target in &member_peer_ids {
            runtime.send_group_offer(&org_pubkey, target, &invite_uri, label.clone())?;
        }
    }
    Ok(())
}
