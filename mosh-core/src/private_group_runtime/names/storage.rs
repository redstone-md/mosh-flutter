use super::*;
use crate::sender_auth::VerifiedSender;

impl GroupSession {
    fn verify_name(
        &self,
        certificate: &NameCertificate,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let change = &certificate.change;
        let proof: SenderProof = decode_json(&certificate.proof)?;
        let sender = proof
            .verify(&OrgContext {
                org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &self.mesh_id,
                channel_kind: &self.control_channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        let authenticated: NameChange = decode_json(&sender.payload)?;
        if authenticated != *change
            || change.group_id != self.group_id
            || change.revision.actor != hex::encode(&sender.mls_signer)
            || change.revision.counter == 0
            || change.revision.counter == u64::MAX
            || crate::chat_names::validate_chat_name(&change.name)
                .map_err(|e| PrivateGroupError::InvalidName(e.to_string()))?
                != change.name
        {
            return Err(PrivateGroupError::Codec("invalid name certificate".into()));
        }
        Ok(sender)
    }

    pub(super) fn install_name(
        &mut self,
        certificate: NameCertificate,
        pending: bool,
    ) -> Result<(), PrivateGroupError> {
        let sender = self.verify_name(&certificate)?;
        let mut names = self.names.clone();
        if pending && !names.pending {
            names.previous = names.current.clone();
            names.previous_label = self.label.clone();
        }
        names.current = Some(certificate.clone());
        names.pending = pending;
        names.error = None;
        let event = certificate.change.event(sender.peer_id, pending);
        let mut events = self.queued_name_events(None, Some("superseded"));
        events.push(event);
        self.save_names(names, Some(certificate.change.name.clone()), &events)?;
        for event in events {
            self.messages.upsert(event);
        }
        Ok(())
    }

    fn save_names(
        &mut self,
        names: GroupNames,
        label: Option<String>,
        events: &[GroupMessage],
    ) -> Result<(), PrivateGroupError> {
        let mut record = self.to_persisted_record();
        record.names = names.clone();
        record.label = label.clone();
        let record =
            serde_json::to_vec(&record).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        self.persistence
            .as_ref()
            .ok_or_else(|| {
                PrivateGroupError::Persistence("name changes require encrypted storage".into())
            })?
            .put_group_name(&self.group_id, &record, &self.crypto.snapshot(), events)?;
        self.names = names;
        self.label = label;
        Ok(())
    }

    pub(super) fn finish_pending_name(&mut self, rejected: bool) -> Result<(), PrivateGroupError> {
        let mut names = self.names.clone();
        let label = if rejected {
            names.current = names.previous.take();
            names.error = Some("permission_changed".into());
            names.previous_label.take()
        } else {
            names.previous = None;
            names.previous_label = None;
            self.label.clone()
        };
        names.pending = false;
        let id = self.names.current.as_ref().map(|c| c.change.event_id());
        let events =
            self.queued_name_events(id.as_deref(), rejected.then_some("permission_changed"));
        self.save_names(names, label, &events)?;
        for event in events {
            self.messages.upsert(event);
        }
        Ok(())
    }
    fn queued_name_events(&self, id: Option<&str>, error: Option<&str>) -> Vec<GroupMessage> {
        self.messages
            .iter()
            .filter(|m| {
                m.name_change.is_some()
                    && m.delivery_status == Some(MessageDeliveryStatus::Queued)
                    && id.is_none_or(|id| m.message_id.as_deref() == Some(id))
            })
            .cloned()
            .map(|mut m| {
                m.delivery_status = Some(if error.is_some() {
                    MessageDeliveryStatus::Failed
                } else {
                    MessageDeliveryStatus::Sent
                });
                m.delivery_error = error.map(str::to_owned);
                m
            })
            .collect()
    }
}

impl NameChange {
    fn event_id(&self) -> String {
        format!(
            "group-name:{}:{}:{}:{}",
            self.revision.epoch,
            self.revision.roster_version,
            self.revision.counter,
            self.revision.actor
        )
    }

    fn event(&self, peer_id: String, pending: bool) -> GroupMessage {
        GroupMessage {
            from_device: self.from_device.clone(),
            from_fingerprint: peer_id,
            body: String::new(),
            message_id: Some(self.event_id()),
            sent_at_ms: Some(self.sent_at_ms),
            attachment: None,
            delivery_status: pending.then_some(MessageDeliveryStatus::Queued),
            delivery_error: None,
            retryable: None,
            retry_count: None,
            name_change: Some(GroupNameChanged {
                name: self.name.clone(),
            }),
        }
    }
}
