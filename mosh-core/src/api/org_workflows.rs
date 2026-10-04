use super::*;
use crate::private_dm_runtime::PrivateDmRuntime;
use crate::private_group_runtime::PrivateGroupRuntime;

pub(super) fn create_and_offer_dm(
    org: &mut OrgRuntime,
    dm: &mut PrivateDmRuntime,
    org_pubkey: &str,
    target_peer_id: &str,
    request: StartSessionRequest,
) -> Result<InviteCreated, ConversationBridgeError> {
    let invite = dm.create_targeted_invite(request, target_peer_id)?;
    if let Err(error) = org.send_dm_offer(org_pubkey, target_peer_id, &invite.invite_uri) {
        let _ = dm.close_session(&invite.session_id);
        return Err(error.into());
    }
    // Publication succeeded: subsequent persistence errors must leave the invite usable.
    org.link_dm(org_pubkey, target_peer_id, &invite.session_id)?;
    Ok(invite)
}

pub(super) fn accept_and_link_dm(
    org: &mut OrgRuntime,
    dm: &mut PrivateDmRuntime,
    org_pubkey: &str,
    offer_id: &str,
    request: AcceptInviteRequest,
) -> Result<SessionSnapshot, ConversationBridgeError> {
    let recovery = org.offer_recovery(org_pubkey, offer_id)?;
    let id = dm.prepare_invite_restoring(request, recovery)?;
    if let Err(error) = register_prepared_dm(org, dm, org_pubkey, offer_id, &id) {
        dm.discard_prepared_join(&id);
        return Err(error);
    }
    if let Err(error) = dm.publish_prepared_join(&id) {
        dm.discard_prepared_join(&id);
        org.reexpose_acceptance(org_pubkey, offer_id);
        return Err(error.into());
    }
    // Native persistence retires the intent atomically; no org write follows it.
    dm.poll_session(&id).map_err(Into::into)
}

fn register_prepared_dm(
    org: &mut OrgRuntime,
    dm: &mut PrivateDmRuntime,
    org_pubkey: &str,
    offer_id: &str,
    id: &str,
) -> Result<(), ConversationBridgeError> {
    let signer = dm.session_signer_public(id)?;
    let recovery = dm.join_recovery(id)?;
    org.complete_dm_offer(org_pubkey, offer_id, id, signer, recovery)
        .map_err(Into::into)
}

pub(super) fn create_and_offer_group(
    org: &mut OrgRuntime,
    groups: &mut PrivateGroupRuntime,
    org_pubkey: &str,
    targets: &[String],
    request: CreateGroupRequest,
) -> Result<GroupCreated, ConversationBridgeError> {
    org.validate_group_targets(org_pubkey, targets)?;
    let created = groups.create_group(request)?;
    offer_created_group(org_pubkey, targets, |target| {
        org.send_group_offer(
            org_pubkey,
            target,
            &created.invite_uri,
            created.label.clone(),
        )
    });
    Ok(created)
}

/// Creation is durable before publication; retain its result and try every peer.
pub(super) fn offer_created_group(
    org_pubkey: &str,
    targets: &[String],
    mut publish: impl FnMut(&str) -> Result<(), OrgError>,
) {
    for target in targets {
        if let Err(error) = publish(target) {
            crate::diagnostics_log::write(
                crate::diagnostics_log::LogLevel::Warn,
                crate::diagnostics_log::kinds::PUBLISH,
                org_pubkey,
                &format!("group invitation to {target} failed: {error}"),
            );
        }
    }
}

pub(crate) fn accept_and_join_group(
    org: &mut OrgRuntime,
    groups: &mut PrivateGroupRuntime,
    org_pubkey: &str,
    offer_id: &str,
    request: JoinGroupRequest,
) -> Result<GroupSnapshot, ConversationBridgeError> {
    let recovery = org.offer_recovery(org_pubkey, offer_id)?;
    let id = groups.prepare_group_restoring(request, recovery)?;
    if let Err(error) = register_prepared_group(org, groups, org_pubkey, offer_id, &id) {
        groups.discard_prepared_join(&id);
        return Err(error);
    }
    if let Err(error) = groups.publish_prepared_join(&id) {
        groups.discard_prepared_join(&id);
        org.reexpose_acceptance(org_pubkey, offer_id);
        return Err(error.into());
    }
    groups.poll(&id).map_err(Into::into)
}

pub(crate) fn register_prepared_group(
    org: &mut OrgRuntime,
    groups: &mut PrivateGroupRuntime,
    org_pubkey: &str,
    offer_id: &str,
    id: &str,
) -> Result<(), ConversationBridgeError> {
    let signer = groups.group_signer_public(id)?;
    let recovery = groups.join_recovery(id)?;
    org.complete_group_offer(org_pubkey, offer_id, id, signer, recovery)
        .map_err(Into::into)
}
