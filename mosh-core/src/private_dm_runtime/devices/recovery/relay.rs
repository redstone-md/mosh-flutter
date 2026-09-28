use super::*;

impl PrivateDmSession {
    pub(in crate::private_dm_runtime::devices) fn authorize_roster_relay(
        &self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
    ) -> Result<()> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        membership
            .topology
            .validate(&self.session_id, &self.crypto.member_signers())?;
        let current = membership
            .current_roster(&roster.user_id())
            .ok_or_else(invalid)?;
        let effective = if roster.extends(current).map_err(|_| invalid())? {
            roster
        } else if current.extends(roster).map_err(|_| invalid())? {
            current
        } else {
            return Err(invalid());
        };
        if membership.revoked
            || membership.joining.is_some()
            || !self.peer_joined
            || !effective.devices().map_err(|_| invalid())?.contains(sender)
        {
            return Err(invalid());
        }
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn authorize_epoch_relay(
        &self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
    ) -> Result<()> {
        if self.authorize_recovery_device(sender, roster).is_ok() {
            return Ok(());
        }
        if !self.awaiting_device_epoch() {
            return Err(invalid());
        }
        self.authorize_roster_relay(sender, roster)
    }

    pub(super) fn recovery_candidates(&self) -> Result<Vec<DeviceDescriptor>> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let local = membership
            .topology
            .client(&hex::encode(self.crypto.signer_public()))
            .ok_or_else(invalid)?
            .device_id
            .clone();
        let mut candidates: Vec<DeviceDescriptor> = Vec::new();
        if self.awaiting_device_epoch() {
            for roster in &membership.topology.rosters {
                let current = membership
                    .current_roster(&roster.user_id())
                    .ok_or_else(invalid)?;
                candidates.extend(current.devices().map_err(|_| invalid())?);
            }
        } else {
            for client in &membership.topology.clients {
                let device = client.device()?;
                if membership.authorized(&device, &client.roster.user_id()) {
                    candidates.push(device);
                }
            }
        }
        candidates.retain(|device| device.device_id != local);
        candidates.sort_by(|a, b| a.device_id.cmp(&b.device_id));
        candidates.dedup_by(|a, b| a.device_id == b.device_id);
        Ok(candidates)
    }
}
