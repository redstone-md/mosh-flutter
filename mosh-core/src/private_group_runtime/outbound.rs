//! Durable text admission, publication and deliberate retry.

use super::*;

impl PrivateGroupRuntime {
    pub fn send(
        &mut self,
        group_id: &str,
        body: String,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        if body.len() > MAX_BODY_LEN {
            return Err(PrivateGroupError::BodyTooLarge);
        }
        self.drain_inbound()?;
        let prepared = {
            let session = self.group_mut(group_id)?;
            if !session.joined {
                return Err(PrivateGroupError::NotReady);
            }
            let mut message = session.messages.stamp(GroupMessage {
                metadata: None,
                from_device: session.display_name.clone(),
                from_fingerprint: session.device_fingerprint.clone(),
                body,
                message_id: None,
                sent_at_ms: None,
                attachment: None,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
                name_change: None,
            });
            session.sign_text_origin(&mut message)?;
            let (payload, ciphertext_bytes) = session.encode_text(&message)?;
            let owned_group_id = session.group_id.clone();
            session
                .outbox()
                .open(message, owned_group_id, payload, ciphertext_bytes)?
        };
        let result = self.publish_prepared(group_id, prepared, true)?;
        self.groups.persist_tail_logged(KIND);
        Ok(result)
    }

    pub fn retry_message(
        &mut self,
        group_id: &str,
        message_id: &str,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        self.drain_inbound()?;
        let prepared = {
            let session = self.group_mut(group_id)?;
            if !session.joined {
                return Err(PrivateGroupError::NotReady);
            }
            session.prepare_retry(message_id)?;
            session.outbox().reopen(message_id)?
        };
        self.publish_prepared(group_id, prepared, true)
    }

    /// Signals "I am typing" in one group, driven by the composer's input.
    /// The per-keystroke call is folded down to the refresh cadence inside
    /// the session; a publish the transport refuses is retried on the next
    /// call (no error to the composer — a dropped hint only delays a hint).
    pub fn typing_signal(&mut self, group_id: &str) -> Result<(), PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        session.publish_typing(now_ms());
        Ok(())
    }

    pub(super) fn persist_prepared(
        &mut self,
        group_id: &str,
        message_id: &str,
        persist_snapshot: bool,
    ) -> Result<(), PrivateGroupError> {
        if let Err(error) = self
            .groups
            .persist_send(group_id, message_id, persist_snapshot)
        {
            self.group_mut(group_id)?.outbox().settle(
                message_id,
                Err(error.to_string()),
                OnSent::Retain,
            )?;
            if let Err(save_error) =
                self.groups
                    .persist_send(group_id, message_id, persist_snapshot)
            {
                dlog::write(
                    LogLevel::Error,
                    kinds::PERSIST,
                    group_id,
                    &save_error.to_string(),
                );
            }
            return Err(error.into());
        }
        Ok(())
    }

    /// Publishes a prepared send on the group's data channel and writes down
    /// how it went. A group has no acknowledgement, so the attempt record is
    /// gone as soon as the frame is on the wire.
    pub(super) fn publish_prepared(
        &mut self,
        group_id: &str,
        prepared: Prepared,
        persist_snapshot: bool,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        self.persist_prepared(group_id, &prepared.message_id, persist_snapshot)?;
        let publish = {
            let session = self
                .groups
                .get(group_id)
                .ok_or_else(|| PrivateGroupError::MissingGroup(group_id.to_string()))?;
            session
                .node
                .publish_room(&session.mesh_id, &session.data_channel, &prepared.payload)
                .map_err(|error| PrivateGroupError::Moss(error.to_string()))
        };
        let (group_id_owned, settled) = {
            let session = self.group_mut(group_id)?;
            let group_id_owned = session.group_id.clone();
            let settled = session.outbox().settle(
                &prepared.message_id,
                publish.map_err(|error| error.to_string()),
                OnSent::Forget,
            )?;
            (group_id_owned, settled)
        };
        if let Err(error) = self
            .groups
            .persist_send(group_id, &prepared.message_id, false)
        {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                group_id,
                &error.to_string(),
            );
        }
        Ok(GroupSendResult {
            group_id: group_id_owned,
            bytes: prepared.ciphertext_bytes,
            message_id: prepared.message_id,
            sent_at_ms: prepared.sent_at_ms,
            delivery_status: settled.status,
            delivery_error: settled.error,
        })
    }
}

impl GroupSession {
    fn sign_text_origin(&self, message: &mut GroupMessage) -> Result<(), PrivateGroupError> {
        message.metadata = Some(crate::message_deletion::MessageMetadata {
            origin: Some(
                crate::message_deletion::MessageOrigin::sign_mls(
                    &format!("group:{}", self.group_id),
                    message.message_id.as_deref().unwrap_or_default(),
                    message.body.as_bytes(),
                    &self.crypto,
                    self.deletions.store.as_ref(),
                    Some(self.device_fingerprint.as_str()),
                )
                .map_err(PrivateGroupError::Codec)?,
            ),
            is_own: Some(true),
            ..Default::default()
        });
        Ok(())
    }
}
