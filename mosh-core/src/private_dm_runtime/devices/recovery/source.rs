use super::super::proof::DevicePacket;
use super::super::runtime::send_packet;
use super::*;
use crate::device_link::identity::DeviceIdentity;

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime::devices) fn receive_recovery_probe(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        probe: RecoveryProbe,
    ) -> Result<()> {
        let session = self.session_ref(&probe.session_id)?;
        session.authorize_recovery_device(sender, roster)?;
        if probe.request_id.is_empty() || probe.request_id.len() > 128 || probe.round == 0 {
            return Err(invalid());
        }
        let offer = RecoveryOffer {
            epoch: session.crypto.epoch().ok_or_else(invalid)?,
            manifest: session.recovery_manifest()?,
            probe,
        };
        send_packet(
            &self.transport,
            identity,
            &sender.moss_peer_id,
            DeviceMessage::RecoveryOffer(offer),
        )
    }

    pub(in crate::private_dm_runtime::devices) fn receive_recovery_pull(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        pull: RecoveryPull,
    ) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&pull.request.session_id)?;
        session.authorize_recovery_device(sender, roster)?;
        if pull.epoch < session.crypto.epoch().ok_or_else(invalid)? {
            let evidence = session
                .membership
                .as_ref()
                .ok_or_else(invalid)?
                .epoch_records
                .iter()
                .find(|record| Some(record.epoch) == pull.epoch.checked_add(1))
                .ok_or_else(invalid)?
                .clone();
            return send_packet(
                &self.transport,
                identity,
                &sender.moss_peer_id,
                DeviceMessage::RecoveryEpoch(RecoveryEpoch {
                    round: pull.round,
                    request_id: pull.request.request_id,
                    evidence,
                }),
            );
        }
        let export = session.recovery_export(&store, sender, &pull)?;
        let mut batch = RecoveryBatch {
            round: pull.round,
            batch: export.batch(&store, &pull.request)?,
        };
        while !fits_stream(
            identity,
            &sender.moss_peer_id,
            &DeviceMessage::RecoveryBatch(batch.clone()),
        ) {
            batch.batch.shrink()?;
        }
        send_packet(
            &self.transport,
            identity,
            &sender.moss_peer_id,
            DeviceMessage::RecoveryBatch(batch),
        )
    }
}

impl PrivateDmSession {
    fn recovery_export(
        &mut self,
        store: &Persistence,
        sender: &DeviceDescriptor,
        pull: &RecoveryPull,
    ) -> Result<HistoryExport> {
        let mut next = self.membership.clone().ok_or_else(invalid)?;
        if let Some(previous) = next
            .recovery_exports
            .iter()
            .find(|item| item.export.recipient_device_id == sender.device_id)
        {
            if previous.round > pull.round {
                return Err(invalid());
            }
            if previous.round == pull.round {
                return if previous.export.request_id == pull.request.request_id {
                    Ok(previous.export.clone())
                } else {
                    Err(invalid())
                };
            }
        }
        if pull.round == 0
            || pull.request.offset != 0
            || pull.request.body_offset != 0
            || pull.request.request_id.is_empty()
            || pull.request.request_id.len() > 128
        {
            return Err(invalid());
        }
        let export = HistoryExport::freeze(self, sender, &pull.request)?;
        next.recovery_exports
            .retain(|item| item.export.recipient_device_id != sender.device_id);
        next.recovery_exports.push(RecoveryExport {
            round: pull.round,
            export: export.clone(),
        });
        self.save_recovery_membership(store, next)?;
        Ok(export)
    }
}

pub(super) fn fits_stream(identity: &DeviceIdentity, peer: &str, message: &DeviceMessage) -> bool {
    DevicePacket::seal(identity, peer, message.clone())
        .ok()
        .and_then(|packet| {
            crate::stream_transport::frame_for_channel(super::super::DEVICE_CHANNEL, &packet)
        })
        .is_some_and(|frame| frame.len() <= 64 * 1024)
}
