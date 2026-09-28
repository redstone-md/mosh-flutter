use super::*;

impl PrivateDmSession {
    pub(super) fn authorize_removal_relay(
        &self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
    ) -> Result<()> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let client = membership
            .topology
            .clients
            .iter()
            .find(|c| c.device_id == sender.device_id)
            .ok_or_else(invalid)?;
        let current = membership
            .topology
            .roster(&roster.user_id())
            .ok_or_else(invalid)?;
        if !membership.authorized(sender, &roster.user_id())
            || client.device()? != *sender
            || !(current.extends(roster).map_err(|_| invalid())?
                || roster.extends(current).map_err(|_| invalid())?)
        {
            return Err(invalid());
        }
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn removal_packets(
        &self,
    ) -> Vec<(String, DeviceMessage)> {
        let Some(membership) = &self.membership else {
            return Vec::new();
        };
        if membership.revoked {
            return Vec::new();
        }
        membership
            .removals
            .iter()
            .flat_map(|journal| {
                journal.waiting.iter().map(|peer| {
                    (
                        peer.clone(),
                        DeviceMessage::Removal(journal.evidence.clone()),
                    )
                })
            })
            .collect()
    }
}

impl PrivateDmRuntime {
    pub(super) fn send_removal_ack(
        &self,
        identity: &DeviceIdentity,
        recipient: &DeviceDescriptor,
        evidence: &RemovalRecord,
    ) -> Result<()> {
        send_packet(
            &self.transport,
            identity,
            &recipient.moss_peer_id,
            DeviceMessage::RemovalAck {
                session_id: evidence.session_id.clone(),
                epoch: evidence.epoch,
                evidence: evidence.digest()?,
            },
        )
    }

    pub(in crate::private_dm_runtime::devices) fn acknowledge_removal(
        &mut self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        id: &str,
        epoch: u64,
        digest: &str,
    ) -> Result<()> {
        let session = self.session_mut(id)?;
        session.authorize_removal_relay(sender, roster)?;
        let mut next = session.membership.clone().ok_or_else(invalid)?;
        let journal = next
            .removals
            .iter_mut()
            .find(|r| r.evidence.epoch == epoch)
            .ok_or_else(invalid)?;
        if journal.evidence.digest()? != digest {
            return Err(invalid());
        }
        journal.waiting.retain(|peer| peer != &sender.moss_peer_id);
        let store = session.device_store.clone().ok_or_else(invalid)?;
        session.save_recovery_membership(&store, next)
    }
}
