use super::super::recovery::RecoveryRemoval;
use super::*;
use crate::private_dm_runtime::now_ms;

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime::devices) fn receive_recovery_removal(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        response: RecoveryRemoval,
    ) -> Result<()> {
        let id = &response.evidence.session_id;
        let session = self.session_ref(id)?;
        session.authorize_removal_relay(sender, roster)?;
        let recovery = session
            .membership
            .as_ref()
            .and_then(|m| m.recovery.as_ref())
            .ok_or_else(invalid)?;
        let source = recovery.source.as_ref().ok_or_else(invalid)?;
        if source.device_id != sender.device_id
            || recovery.round != response.round
            || source.import.request_id != response.request_id
        {
            return Err(invalid());
        }
        let (crypto, mut next) =
            transition::stage_removal(session, &response.evidence, &identity.device().device_id)?;
        let recovery = next.recovery.as_mut().ok_or_else(invalid)?;
        recovery.last_rx_ms = now_ms();
        let source = recovery.source.as_mut().ok_or_else(invalid)?;
        source.epoch = source.epoch.max(response.evidence.epoch);
        self.install_device_transition(id, crypto, next)?;
        self.adopt_own_removal(&response.evidence)?;
        self.session_mut(id)?.history_last_rx_ms = now_ms();
        self.send_removal_ack(identity, sender, &response.evidence)
    }
}
