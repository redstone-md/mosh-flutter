use super::super::{proof::DevicePacket, runtime::send_packet, types::DeviceMessage};
use super::{records::TextRecord, types::*, *};
use crate::conversation::history::StoredMessage;
use crate::persistence::Persistence;
use crate::private_dm_runtime::PrivateDmRuntime;
use sha2::{Digest, Sha256};

// Moss's default application payload ceiling applies after our base64 framing.
impl HistoryExport {
    pub(in crate::private_dm_runtime::devices) fn freeze(
        session: &PrivateDmSession,
        sender: &DeviceDescriptor,
        request: &HistoryRequest,
    ) -> Result<Self> {
        let keys = Self::keys(session)?;
        let json = serde_json::to_vec(&keys).map_err(|_| invalid())?;
        Ok(Self {
            request_id: request.request_id.clone(),
            recipient_device_id: sender.device_id.clone(),
            keys,
            digest: hex::encode(Sha256::digest(json)),
        })
    }

    pub(in crate::private_dm_runtime::devices) fn keys(
        session: &PrivateDmSession,
    ) -> Result<Vec<HistoryKey>> {
        let mut keys = Vec::new();
        for message in session.messages.iter() {
            if let Some(record) = TextRecord::from_message(message) {
                record.validate()?;
                keys.push(HistoryKey {
                    message_id: record.message_id,
                    sent_at_ms: record.sent_at_ms,
                });
            }
        }
        keys.sort_by(|a, b| (a.sent_at_ms, &a.message_id).cmp(&(b.sent_at_ms, &b.message_id)));
        Ok(keys)
    }

    pub(in crate::private_dm_runtime::devices) fn batch(
        &self,
        store: &Persistence,
        request: &HistoryRequest,
    ) -> Result<HistoryBatch> {
        if request.offset > self.keys.len() {
            return Err(invalid());
        }
        let mut records = Vec::new();
        for key in self.keys.iter().skip(request.offset).take(BATCH_RECORDS) {
            let bytes = store
                .get_dm_history_message(&request.session_id, key.sent_at_ms, &key.message_id)?
                .ok_or_else(invalid)?;
            let mut stored: StoredMessage<crate::private_dm_runtime::ChatMessage> =
                serde_json::from_slice(&bytes).map_err(|_| invalid())?;
            if stored.conversation_id != request.session_id
                || stored.message_id != key.message_id
                || stored.sent_at_ms != key.sent_at_ms
            {
                return Err(invalid());
            }
            stored.message.message_id = Some(stored.message_id);
            stored.message.sent_at_ms = Some(stored.sent_at_ms);
            let record = TextRecord::from_message(&stored.message).ok_or_else(invalid)?;
            record.validate()?;
            records.push(record);
        }
        let mut batch = HistoryBatch {
            session_id: request.session_id.clone(),
            request_id: self.request_id.clone(),
            offset: request.offset,
            total: self.keys.len(),
            manifest: self.digest.clone(),
            records,
            fragment: None,
        };
        if request.body_offset > 0 {
            batch.fragment_first(request.body_offset)?;
        }
        Ok(batch)
    }
}

impl PrivateDmSession {
    fn history_export(
        &mut self,
        store: &Persistence,
        sender: &DeviceDescriptor,
        request: &HistoryRequest,
    ) -> Result<HistoryExport> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        if let Some(export) = membership
            .history_exports
            .iter()
            .find(|export| export.recipient_device_id == sender.device_id)
        {
            return if export.request_id == request.request_id {
                Ok(export.clone())
            } else {
                Err(invalid())
            };
        }
        if request.offset != 0
            || request.body_offset != 0
            || request.request_id.is_empty()
            || request.request_id.len() > 128
        {
            return Err(invalid());
        }
        let export = HistoryExport::freeze(self, sender, request)?;
        let mut next = membership.clone();
        next.history_exports.push(export.clone());
        let mut record = self.to_persisted_record();
        record.membership = Some(next.clone());
        store.put_session(
            &self.session_id,
            &serde_json::to_vec(&record).map_err(|_| invalid())?,
        )?;
        self.membership = Some(next);
        Ok(export)
    }
}

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime) fn receive_history_request(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        request: HistoryRequest,
    ) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&request.session_id)?;
        session.authorize_history_device(identity, sender, roster)?;
        let export = session.history_export(&store, sender, &request)?;
        let mut batch = export.batch(&store, &request)?;
        while !DevicePacket::fits_stream(
            identity,
            &sender.moss_peer_id,
            DeviceMessage::HistoryBatch(batch.clone()),
        ) {
            batch.shrink()?;
        }
        send_packet(
            &self.transport,
            identity,
            &sender.moss_peer_id,
            DeviceMessage::HistoryBatch(batch),
        )
    }
}
