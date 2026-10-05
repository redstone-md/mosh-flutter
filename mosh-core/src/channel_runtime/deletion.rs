use super::*;
use crate::message_deletion::{
    authority::DeletionAuthority,
    cipher,
    protocol::{DeletionFrame, DeletionMessage},
    shared::{self, DeletionActor},
    types::DeleteMessagesResult,
    DeleteScope, DeletionContext,
};
use ed25519_dalek::Signer;

impl ChannelRuntime {
    pub fn delete_messages(
        &mut self,
        id: &str,
        messages: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, ChannelRuntimeError> {
        self.drain_inbound()?;
        self.channels.persist_tail()?;
        let session = self.channel_mut(&normalize_name(id)?)?;
        session.delete_messages(messages, scope)
    }
}

impl ChannelSession {
    fn delete_messages(
        &mut self,
        ids: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, ChannelRuntimeError> {
        if scope == DeleteScope::ForMe {
            let _ = crate::message_deletion::ownership::create(
                self.deletions.store.as_ref(),
                Some(self.device_fingerprint.as_str()),
                &self.device_fingerprint,
            )
            .map_err(ChannelRuntimeError::Codec)?;
            return self
                .deletions
                .delete_for_me(
                    &mut self.messages,
                    &mut self.outbound_attempts,
                    &mut self.transfer,
                    ids,
                )
                .map_err(ChannelRuntimeError::Persistence);
        }
        let authority = self.deletion_authority()?;
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        let result = shared::admit(
            &mut self.deletions,
            &mut self.messages,
            &mut self.outbound_attempts,
            &mut self.transfer,
            ids,
            &authority.local,
            |m| {
                m.metadata
                    .as_ref()
                    .and_then(|m| m.origin.as_ref())
                    .and_then(|o| authority.permitted(o))
            },
            |bytes| Ok(hex::encode(key.sign(bytes).to_bytes())),
        )
        .map_err(ChannelRuntimeError::Codec)?;
        self.deletions.last_sync = 0;
        let _ = self.publish_deletion(&shared::page(&self.deletions, None, &authority));
        Ok(result)
    }

    pub(super) fn deletion_authority(&self) -> Result<DeletionAuthority, ChannelRuntimeError> {
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        Ok(DeletionAuthority {
            local: DeletionActor {
                key: hex::encode(key.verifying_key().as_bytes()),
                name: self.display_name.clone(),
                epoch: 0,
                ownership: crate::message_deletion::ownership::create(
                    self.deletions.store.as_ref(),
                    Some(self.device_fingerprint.as_str()),
                    &hex::encode(key.verifying_key().as_bytes()),
                )
                .map_err(ChannelRuntimeError::Codec)?,
            },
            members: Default::default(),
            admins: Default::default(),
            past_admins: Default::default(),
            accounts: Default::default(),
            public_channel: true,
        })
    }

    pub(super) fn apply_deletions(&mut self) -> Result<(), ChannelRuntimeError> {
        self.deletions
            .apply(
                &mut self.messages,
                &mut self.outbound_attempts,
                &mut self.transfer,
            )
            .map_err(ChannelRuntimeError::Persistence)
    }

    pub(super) fn receive_deletion_frame(
        &mut self,
        frame: DeletionFrame,
    ) -> Result<(), ChannelRuntimeError> {
        let authority = self.deletion_authority()?;
        if frame.author == authority.local.key {
            return Ok(());
        }
        let message = cipher::open_channel(&self.deletions.context, &frame)
            .map_err(ChannelRuntimeError::Codec)?;
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        let replies = DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .receive(message, &frame.author, &authority, |bytes| {
            Ok(hex::encode(key.sign(bytes).to_bytes()))
        })
        .map_err(ChannelRuntimeError::Codec)?;
        for reply in replies {
            self.publish_deletion(&reply)?;
        }
        Ok(())
    }

    fn publish_deletion(&mut self, message: &DeletionMessage) -> Result<(), ChannelRuntimeError> {
        for message in crate::message_deletion::fragments::split(message)
            .map_err(ChannelRuntimeError::Codec)?
        {
            let frame = cipher::seal_channel(
                &self.deletions.context,
                self.node
                    .identity_signer()
                    .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?,
                &message,
            )
            .map_err(ChannelRuntimeError::Codec)?;
            publish_json(
                &self.node,
                &self.mesh_id,
                &self.blob_topic,
                &ChannelBlobEnvelope::MessageDeletion { frame },
            )?;
        }
        Ok(())
    }

    pub(super) fn sync_deletions(&mut self, now: u64) -> Result<(), ChannelRuntimeError> {
        if self.deletions.records.is_empty() {
            return Ok(());
        }
        if now.saturating_sub(self.deletions.last_sync) < 2000 {
            return Ok(());
        }
        let authority = self.deletion_authority()?;
        self.deletions.last_sync = now;
        let digest =
            shared::digest(&self.deletions, &authority).map_err(ChannelRuntimeError::Codec)?;
        self.publish_deletion(&DeletionMessage::Request {
            after: None,
            digest: Some(digest),
        })
    }
}
