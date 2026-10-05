use super::*;
use crate::message_deletion::{
    authority::DeletionAuthority,
    cipher,
    protocol::{DeletionFrame, DeletionMessage},
    shared::{self, DeletionActor},
    types::DeleteMessagesResult,
    DeleteScope, DeletionContext,
};

impl PrivateDmRuntime {
    pub fn delete_messages(
        &mut self,
        id: &str,
        messages: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, PrivateDmRuntimeError> {
        self.receive_inbound();
        self.sessions.persist_tail()?;
        let session = self.session_mut(id)?;
        session.delete_messages(messages, scope)
    }
}

impl PrivateDmSession {
    fn delete_messages(
        &mut self,
        ids: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, PrivateDmRuntimeError> {
        if scope == DeleteScope::ForMe {
            return crate::message_deletion::delete_for_me(
                &mut DeletionContext {
                    book: &mut self.deletions,
                    log: &mut self.messages,
                    attempts: &mut self.outbound_attempts,
                    transfer: &mut self.transfer,
                },
                ids,
                self.transport.local_peer_id().as_deref(),
            )
            .map_err(PrivateDmRuntimeError::Deletion);
        }
        let authority = self.deletion_authority()?;

        let result = shared::admit(
            &mut DeletionContext {
                book: &mut self.deletions,
                log: &mut self.messages,
                attempts: &mut self.outbound_attempts,
                transfer: &mut self.transfer,
            },
            ids,
            &authority.local,
            |m| {
                m.metadata
                    .as_ref()
                    .and_then(|m| m.origin.as_ref())
                    .and_then(|o| authority.permitted(o))
            },
            |bytes| {
                self.crypto
                    .sign_sender_proof(bytes)
                    .map(hex::encode)
                    .map_err(|e| e.to_string())
            },
        )
        .map_err(PrivateDmRuntimeError::Deletion)?;
        self.deletions.last_sync = 0;
        let _ = self.publish_deletion(&shared::page(&self.deletions, None, &authority));
        Ok(result)
    }

    pub(super) fn deletion_authority(
        &mut self,
    ) -> Result<DeletionAuthority, PrivateDmRuntimeError> {
        let local = DeletionActor {
            key: hex::encode(self.crypto.signer_public()),
            name: self
                .device_id
                .chars()
                .take(64)
                .filter(|c| !c.is_control())
                .collect(),
            epoch: self.crypto.epoch().unwrap_or_default(),
            ownership: crate::message_deletion::ownership::create(
                self.deletions.store.as_ref(),
                self.transport.local_peer_id().as_deref(),
                &hex::encode(self.crypto.signer_public()),
            )
            .map_err(PrivateDmRuntimeError::Deletion)?,
        };
        let members = self.crypto.member_signers().into_iter().collect();
        let mut authority = DeletionAuthority {
            local,
            members,
            admins: Default::default(),
            accepted: self.deletions.accepted.clone(),
            accounts: Default::default(),
            own: Default::default(),
            public_channel: false,
        };
        self.fill_deletion_accounts(&mut authority);
        Ok(authority)
    }

    pub(super) fn apply_deletions(&mut self) -> Result<(), PrivateDmRuntimeError> {
        crate::message_deletion::apply(&mut DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        })
        .map_err(PrivateDmRuntimeError::Persistence)
    }

    pub(super) fn receive_deletion_frame(
        &mut self,
        frame: DeletionFrame,
    ) -> Result<(), PrivateDmRuntimeError> {
        let authority = self.deletion_authority()?;
        if frame.author == authority.local.key {
            return Ok(());
        }
        let message = cipher::open_mls(&self.deletions.context, &self.crypto, &frame)
            .map_err(PrivateDmRuntimeError::Codec)?;

        let replies = DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .receive(message, &frame.author, &authority, |bytes| {
            self.crypto
                .sign_sender_proof(bytes)
                .map(hex::encode)
                .map_err(|e| e.to_string())
        })
        .map_err(PrivateDmRuntimeError::Codec)?;
        for reply in replies {
            self.publish_deletion(&reply)?;
        }
        Ok(())
    }

    fn publish_deletion(&mut self, message: &DeletionMessage) -> Result<(), PrivateDmRuntimeError> {
        for message in crate::message_deletion::fragments::split(message)
            .map_err(PrivateDmRuntimeError::Codec)?
        {
            let frame = cipher::seal_mls(&self.deletions.context, &self.crypto, &message)
                .map_err(PrivateDmRuntimeError::Codec)?;
            let envelope = ControlEnvelope::MessageDeletion {
                session_id: self.session_id.clone(),
                frame,
            };
            let bytes = serde_json::to_vec(&envelope)
                .map_err(|e| PrivateDmRuntimeError::Codec(e.to_string()))?;
            self.route_send(ChannelKind::Control, &bytes)?;
        }
        Ok(())
    }

    pub(super) fn sync_deletions(&mut self, now: u64) -> Result<(), PrivateDmRuntimeError> {
        if self.deletions.records.is_empty() {
            return Ok(());
        }
        if !(self.crypto.is_ready()) || now.saturating_sub(self.deletions.last_sync) < 2000 {
            return Ok(());
        }
        let authority = self.deletion_authority()?;
        self.deletions.last_sync = now;
        let digest =
            shared::digest(&self.deletions, &authority).map_err(PrivateDmRuntimeError::Codec)?;
        self.publish_deletion(&DeletionMessage::Request {
            after: None,
            digest: Some(digest),
        })
    }
}

impl PrivateDmSession {
    fn fill_deletion_accounts(&self, authority: &mut DeletionAuthority) {
        if let Some(membership) = &self.membership {
            authority.accounts = membership.deletion_accounts();
        }
    }
}
