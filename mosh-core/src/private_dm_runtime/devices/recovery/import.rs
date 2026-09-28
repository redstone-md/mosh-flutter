use super::*;
use crate::private_dm_runtime::{now_ms, ChatMessage};

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime::devices) fn receive_recovery_offer(
        &mut self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        offer: RecoveryOffer,
    ) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&offer.probe.session_id)?;
        session.authorize_recovery_device(sender, roster)?;
        let mut next = session.membership.clone().ok_or_else(invalid)?;
        let recovery = next.recovery.as_mut().ok_or_else(invalid)?;
        if recovery.round != offer.probe.round
            || recovery.request_id != offer.probe.request_id
            || offer.manifest.len() != 64
            || hex::decode(&offer.manifest).is_err()
        {
            return Err(invalid());
        }
        recovery.required_epoch = recovery.required_epoch.max(offer.epoch);
        if recovery.source.is_some() {
            return session.save_recovery_membership(&store, next);
        }
        let epoch = session.crypto.epoch().ok_or_else(invalid)?;
        if offer.epoch > epoch
            || (offer.manifest != session.recovery_manifest()?
                && recovery.observed.get(&sender.device_id) != Some(&offer.manifest))
        {
            recovery.source = Some(RecoverySource {
                device_id: sender.device_id.clone(),
                epoch: offer.epoch,
                import: HistoryImport::new(&recovery.request_id, sender),
            });
        } else {
            recovery
                .observed
                .insert(sender.device_id.clone(), offer.manifest);
        }
        recovery.last_rx_ms = now_ms();
        session.history_last_rx_ms = 0;
        session.save_recovery_membership(&store, next)
    }

    pub(in crate::private_dm_runtime::devices) fn receive_recovery_batch(
        &mut self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        response: RecoveryBatch,
    ) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&response.batch.session_id)?;
        session.authorize_recovery_device(sender, roster)?;
        let mut next = session.membership.clone().ok_or_else(invalid)?;
        let recovery = next.recovery.as_mut().ok_or_else(invalid)?;
        let source = recovery.source.as_mut().ok_or_else(invalid)?;
        if recovery.round != response.round
            || source.device_id != sender.device_id
            || session
                .crypto
                .epoch()
                .is_none_or(|epoch| epoch < source.epoch)
        {
            return Err(invalid());
        }
        let rows = session.history_rows(source.import.accept(&response.batch)?)?;
        if source.import.complete {
            recovery
                .observed
                .insert(sender.device_id.clone(), response.batch.manifest);
            recovery.source = None;
        }
        recovery.last_rx_ms = now_ms();
        let mut record = session.to_persisted_record();
        record.membership = Some(next.clone());
        let bytes = serde_json::to_vec(&record).map_err(|_| invalid())?;
        store.commit_dm_history_import::<ChatMessage>(&session.session_id, &bytes, &rows)?;
        session.membership = Some(next);
        session.history_last_rx_ms = now_ms();
        for row in rows {
            session.messages.push_stamped(row.message);
        }
        Ok(())
    }
}
