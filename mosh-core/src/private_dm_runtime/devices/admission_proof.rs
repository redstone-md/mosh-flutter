//! Verify and stage linked-client MLS admission before durable acceptance.

use super::*;

pub(in crate::private_dm_runtime::devices) fn copy_crypto(
    session: &PrivateDmSession,
) -> Result<MlsSessionCrypto> {
    let signer = session.crypto.signer_public();
    let snapshot = session.crypto.snapshot();
    match session.crypto.group_id_bytes() {
        Some(group) => Ok(MlsSessionCrypto::restore(
            &session.device_id,
            &signer,
            &snapshot,
            &group,
        )?),
        None => Ok(MlsSessionCrypto::restore_unjoined(
            &session.device_id,
            &signer,
            &snapshot,
        )?),
    }
}

pub(in crate::private_dm_runtime::devices) fn verify_request(
    crypto: &MlsSessionCrypto,
    request: &JoinRequest,
) -> Result<()> {
    request.claim.verify(&request.claim.session_id)?;
    if request.request_id.is_empty()
        || request.request_id.len() > MAX_REQUEST_ID_BYTES
        || crypto.key_package_identity(&request.key_package)? != request.claim.device_id
        || crypto.key_package_signer(&request.key_package)? != request.claim.mls_signer
    {
        return Err(invalid());
    }
    Ok(())
}

pub(in crate::private_dm_runtime::devices) fn verify_authorizer(
    membership: &DeviceMembership,
    sender: &DeviceDescriptor,
    roster: &DeviceRoster,
    admission: &Admission,
) -> Result<()> {
    let author = membership
        .topology
        .clients
        .iter()
        .find(|client| client.device_id == sender.device_id)
        .ok_or_else(invalid)?;
    let base = membership
        .topology
        .roster(&roster.user_id())
        .ok_or_else(invalid)?;
    if author.roster.user_id() != admission.request.claim.roster.user_id()
        || roster.user_id() != author.roster.user_id()
        || !roster.extends(base).map_err(|_| invalid())?
        || !admission
            .request
            .claim
            .roster
            .extends(base)
            .map_err(|_| invalid())?
        || !admission
            .request
            .claim
            .roster
            .devices()
            .map_err(|_| invalid())?
            .contains(sender)
    {
        return Err(invalid());
    }
    Ok(())
}

pub(in crate::private_dm_runtime::devices) fn stage_admission(
    session: &PrivateDmSession,
    admission: &Admission,
) -> Result<(MlsSessionCrypto, DeviceMembership)> {
    let mut next = session.membership.clone().ok_or_else(invalid)?;
    let mut crypto = copy_crypto(session)?;
    if let Some(join) = &next.joining {
        if join.request.request_id != admission.request.request_id
            || join.request.key_package != admission.request.key_package
            || join.group_id != admission.group_id
        {
            return Err(invalid());
        }
        crypto.join_welcome(&admission.welcome, &admission.tree)?;
    } else {
        if crypto.epoch().and_then(|epoch| epoch.checked_add(1)) != Some(admission.epoch)
            || crypto.group_id_bytes().as_ref() != Some(&admission.group_id)
        {
            return Err(invalid());
        }
        crypto.process_commit(&admission.commit)?;
    }
    next.topology.add_client(admission.request.claim.clone())?;
    next.topology
        .validate(&session.session_id, &crypto.member_signers())?;
    if crypto.epoch() != Some(admission.epoch)
        || crypto.group_id_bytes().as_ref() != Some(&admission.group_id)
    {
        return Err(invalid());
    }
    next.joining = None;
    Ok((crypto, next))
}
