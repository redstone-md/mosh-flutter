use super::*;

impl PrivateDmRuntime {
    // Ahead evidence is an authenticated recovery hint. Its MLS transition is
    // verified only after the preceding commits establish the exact topology.
    pub(super) fn bootstrap_future_removal(
        &mut self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        evidence: &RemovalRecord,
    ) -> Result<bool> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&evidence.session_id)?;
        let epoch = session.crypto.epoch().ok_or_else(invalid)?;
        if evidence.epoch <= epoch.checked_add(1).ok_or_else(invalid)? {
            return Ok(false);
        }
        session.authorize_removal_relay(sender, roster)?;
        evidence.verify_author(session)?;
        let mut next = session.membership.clone().ok_or_else(invalid)?;
        next.pin_roster(&evidence.roster)?;
        next.require_epoch(evidence.epoch, epoch);
        session.save_recovery_membership(&store, next)?;
        Ok(true)
    }
}
