use super::*;
use crate::mls_crypto::MlsSessionCrypto;

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime::devices) fn reconcile_revocations(
        &mut self,
        identity: &DeviceIdentity,
    ) -> Result<()> {
        let ids: Vec<_> = self.sessions.iter_mut().map(|(id, _)| id.clone()).collect();
        for id in ids {
            self.note_roster_revocation(&id, identity)?;
            self.originate_removal(&id, identity)?;
        }
        Ok(())
    }

    fn originate_removal(&mut self, id: &str, identity: &DeviceIdentity) -> Result<()> {
        if identity.revoked().map_err(|_| invalid())? {
            return Ok(());
        }
        let session = self.session_ref(id)?;
        let Some(membership) = &session.membership else {
            return Ok(());
        };
        if membership.joining.is_some() || !session.peer_joined {
            return Ok(());
        }
        let Some((target, roster)) = membership.next_local_removal(identity)? else {
            return Ok(());
        };
        let mut crypto = super::super::admission::copy_crypto(session)?;
        let commit = crypto.remove_member_by_signer(&target.mls_signer)?;
        let evidence =
            RemovalRecord::create(identity, id, target.device_id, roster, &crypto, commit)?;
        let next = next_membership(session, &evidence, &crypto, &identity.device().device_id)?;
        self.install_device_transition(id, crypto, next)
    }

    fn note_roster_revocation(&mut self, id: &str, identity: &DeviceIdentity) -> Result<()> {
        let session = self.session_mut(id)?;
        let Some(membership) = &mut session.membership else {
            return Ok(());
        };
        let obsolete_local = membership
            .topology
            .client(&hex::encode(session.crypto.signer_public()))
            .is_some_and(|c| {
                identity
                    .roster()
                    .revoked_since(&c.roster, &c.device_id)
                    .unwrap_or(false)
            });
        if identity.revoked().map_err(|_| invalid())? || obsolete_local {
            membership.revoked = true;
            session.record_dirty = true;
            return Ok(());
        }
        let known = membership.current_roster(&identity.roster().user_id());
        if known.is_some_and(|r| r.digest().ok() == identity.roster().digest().ok()) {
            return Ok(());
        }
        if let Some(base) = known {
            if !identity.roster().extends(base).map_err(|_| invalid())? {
                return Ok(());
            }
        }
        membership
            .pending_rosters
            .retain(|r| r.user_id() != identity.roster().user_id());
        membership.pending_rosters.push(identity.roster().clone());
        session.record_dirty = true;
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn receive_removal(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        evidence: RemovalRecord,
    ) -> Result<()> {
        let session = self.session_ref(&evidence.session_id)?;
        session.authorize_removal_relay(sender, roster)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        if let Some(existing) = membership
            .removals
            .iter()
            .find(|r| r.evidence.epoch == evidence.epoch)
        {
            if existing.evidence.digest()? != evidence.digest()? {
                return Err(invalid());
            }
            self.adopt_own_removal(&evidence)?;
            return self.send_removal_ack(identity, sender, &evidence);
        }
        let (crypto, next) = stage_removal(session, &evidence, &identity.device().device_id)?;
        self.install_device_transition(&evidence.session_id, crypto, next)?;
        self.adopt_own_removal(&evidence)?;
        self.send_removal_ack(identity, sender, &evidence)
    }
}

pub(super) fn stage_removal(
    session: &PrivateDmSession,
    evidence: &RemovalRecord,
    local: &str,
) -> Result<(MlsSessionCrypto, DeviceMembership)> {
    let author = evidence.verify(session)?;
    if session.crypto.epoch().and_then(|e| e.checked_add(1)) != Some(evidence.epoch) {
        return Err(invalid());
    }
    let mut crypto = super::super::admission::copy_crypto(session)?;
    crypto.process_commit_from(&evidence.commit, &author)?;
    let next = next_membership(session, evidence, &crypto, local)?;
    Ok((crypto, next))
}

fn next_membership(
    session: &PrivateDmSession,
    evidence: &RemovalRecord,
    crypto: &MlsSessionCrypto,
    local: &str,
) -> Result<DeviceMembership> {
    let mut next = session.membership.clone().ok_or_else(invalid)?;
    next.forget_removed_peer(&evidence.target)?;
    next.topology
        .clients
        .retain(|c| c.device_id != evidence.target);
    next.topology.update_roster(evidence.roster.clone())?;
    next.topology
        .validate(&session.session_id, &crypto.member_signers())?;
    if crypto.epoch() != Some(evidence.epoch)
        || crypto.group_id_bytes().as_ref() != Some(&evidence.group_id)
    {
        return Err(invalid());
    }
    let signers = crypto.member_signers();
    for targets in next.receipt_targets.values_mut() {
        targets.retain(|s| signers.contains(s));
    }
    next.retain_removal(evidence.clone(), local)?;
    if let Some(recovery) = &mut next.recovery {
        recovery.required_epoch = recovery.required_epoch.max(evidence.epoch);
    }
    Ok(next)
}

impl DeviceMembership {
    // MLS transitions follow signed roster order, regardless of leaf order.
    fn next_local_removal(
        &self,
        identity: &DeviceIdentity,
    ) -> Result<Option<(super::IdentityClaim, DeviceRoster)>> {
        let mut next: Option<(super::IdentityClaim, DeviceRoster)> = None;
        for client in &self.topology.clients {
            if client.roster.user_id() != identity.roster().user_id() {
                continue;
            }
            let Some(roster) = identity
                .roster()
                .first_removal_since(&client.roster, &client.device_id)
                .map_err(|_| invalid())?
            else {
                continue;
            };
            if next
                .as_ref()
                .is_none_or(|(_, previous)| previous.extends(&roster).unwrap_or(false))
            {
                next = Some((client.clone(), roster));
            }
        }
        if let Some((target, roster)) = &next {
            if roster
                .removal_author(&target.device_id)
                .map_err(|_| invalid())?
                .as_deref()
                != Some(&identity.device().device_id)
            {
                return Ok(None);
            }
        }
        Ok(next)
    }

    fn forget_removed_peer(&mut self, target: &str) -> Result<()> {
        let peer = self
            .topology
            .clients
            .iter()
            .find(|c| c.device_id == target)
            .ok_or_else(invalid)?
            .device()?
            .moss_peer_id;
        if self
            .delivery
            .as_ref()
            .is_some_and(|j| j.admission.request.claim.device_id == target)
        {
            self.delivery = None;
        } else if let Some(delivery) = &mut self.delivery {
            delivery.waiting.retain(|p| p != &peer);
        }
        for journal in &mut self.removals {
            journal.waiting.retain(|p| p != &peer);
        }
        self.history_exports
            .retain(|e| e.recipient_device_id != target);
        self.recovery_exports
            .retain(|e| e.export.recipient_device_id != target);
        if self
            .history_import
            .as_ref()
            .is_some_and(|i| i.source_device_id == target && !i.complete)
        {
            self.history_import = None;
        }
        if let Some(recovery) = &mut self.recovery {
            if recovery
                .source
                .as_ref()
                .is_some_and(|s| s.device_id == target)
            {
                recovery.source = None;
                recovery.started_ms = 0;
            }
        }
        Ok(())
    }
}
