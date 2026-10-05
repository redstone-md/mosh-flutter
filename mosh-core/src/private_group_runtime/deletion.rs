use super::*;
use crate::message_deletion::{
    authority::DeletionAuthority,
    cipher,
    protocol::{DeletionFrame, DeletionMessage},
    shared::{self, DeletionActor},
    types::DeleteMessagesResult,
    DeleteScope, DeletionContext,
};

impl PrivateGroupRuntime {
    pub fn delete_messages(
        &mut self,
        id: &str,
        messages: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail()?;
        let session = self.group_mut(id)?;
        session.delete_messages(messages, scope)
    }
}

impl GroupSession {
    fn delete_messages(
        &mut self,
        ids: &[String],
        scope: DeleteScope,
    ) -> Result<DeleteMessagesResult, PrivateGroupError> {
        if scope == DeleteScope::ForMe {
            let _ = crate::message_deletion::ownership::create(
                self.deletions.store.as_ref(),
                Some(self.device_fingerprint.as_str()),
                &hex::encode(self.crypto.signer_public()),
            )
            .map_err(PrivateGroupError::Codec)?;
            return self
                .deletions
                .delete_for_me(
                    &mut self.messages,
                    &mut self.outbound_attempts,
                    &mut self.transfer,
                    ids,
                )
                .map_err(PrivateGroupError::Persistence);
        }
        let authority = self.deletion_authority()?;

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
            |bytes| {
                self.crypto
                    .sign_sender_proof(bytes)
                    .map(hex::encode)
                    .map_err(|e| e.to_string())
            },
        )
        .map_err(PrivateGroupError::Codec)?;
        self.deletions.last_sync = 0;
        let _ = self.publish_deletion(&shared::page(&self.deletions, None, &authority));
        Ok(result)
    }

    pub(super) fn deletion_authority(&mut self) -> Result<DeletionAuthority, PrivateGroupError> {
        let local = DeletionActor {
            key: hex::encode(self.crypto.signer_public()),
            name: self
                .display_name
                .chars()
                .take(64)
                .filter(|c| !c.is_control())
                .collect(),
            epoch: self.crypto.epoch().unwrap_or_default(),
            ownership: crate::message_deletion::ownership::create(
                self.deletions.store.as_ref(),
                Some(self.device_fingerprint.as_str()),
                &hex::encode(self.crypto.signer_public()),
            )
            .map_err(PrivateGroupError::Codec)?,
        };
        let members = self.crypto.member_signers().into_iter().collect();
        let mut authority = DeletionAuthority {
            local,
            members,
            admins: Default::default(),
            past_admins: Default::default(),
            accounts: Default::default(),
            public_channel: false,
        };
        self.fill_deletion_admins(&mut authority)?;
        Ok(authority)
    }

    pub(super) fn apply_deletions(&mut self) -> Result<(), PrivateGroupError> {
        self.deletions
            .apply(
                &mut self.messages,
                &mut self.outbound_attempts,
                &mut self.transfer,
            )
            .map_err(PrivateGroupError::Persistence)
    }

    pub(super) fn receive_deletion_frame(
        &mut self,
        frame: DeletionFrame,
    ) -> Result<(), PrivateGroupError> {
        let authority = self.deletion_authority()?;
        if frame.author == authority.local.key {
            return Ok(());
        }
        let message = cipher::open_mls(&self.deletions.context, &self.crypto, &frame)
            .map_err(PrivateGroupError::Codec)?;

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
        .map_err(PrivateGroupError::Codec)?;
        for reply in replies {
            self.publish_deletion(&reply)?;
        }
        Ok(())
    }

    fn publish_deletion(&mut self, message: &DeletionMessage) -> Result<(), PrivateGroupError> {
        for message in
            crate::message_deletion::fragments::split(message).map_err(PrivateGroupError::Codec)?
        {
            let frame = cipher::seal_mls(&self.deletions.context, &self.crypto, &message)
                .map_err(PrivateGroupError::Codec)?;
            self.publish_control(&ControlEnvelope::MessageDeletion {
                group_id: self.group_id.clone(),
                frame,
            })?;
        }
        Ok(())
    }

    pub(super) fn sync_deletions(&mut self, now: u64) -> Result<(), PrivateGroupError> {
        if self.deletions.records.is_empty() {
            return Ok(());
        }
        if !(self.joined && self.crypto.is_ready())
            || now.saturating_sub(self.deletions.last_sync) < 2000
        {
            return Ok(());
        }
        let authority = self.deletion_authority()?;
        DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .reconcile(&authority, false)
        .map_err(PrivateGroupError::Persistence)?;
        self.deletions.last_sync = now;
        let digest =
            shared::digest(&self.deletions, &authority).map_err(PrivateGroupError::Codec)?;
        self.publish_deletion(&DeletionMessage::Request {
            after: None,
            digest: Some(digest),
        })
    }
}

impl GroupSession {
    fn fill_deletion_admins(
        &mut self,
        authority: &mut DeletionAuthority,
    ) -> Result<(), PrivateGroupError> {
        let roster = if self.org_pubkey.is_some() {
            Some(self.org_roster_checked()?)
        } else {
            None
        };
        for signer in &authority.members {
            let admin = if let Some(roster) = &roster {
                let key =
                    hex::decode(signer).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
                let identity = self.crypto.member_identity_for_signer(&key);
                roster
                    .members
                    .iter()
                    .any(|m| Some(&m.moss_peer_id) == identity.as_ref() && m.role == "admin")
            } else {
                signer
                    .to_uppercase()
                    .starts_with(&self.current_admin_fingerprint)
            };
            if admin {
                authority.admins.insert(signer.clone());
            }
        }
        if let Some(store) = &self.deletions.store {
            authority.past_admins =
                store.remember_deletion_admins(&self.deletions.context, &authority.admins)?;
        }
        Ok(())
    }
}

impl GroupSession {
    pub(super) fn cancel_pending_deletions(&mut self) -> Result<(), PrivateGroupError> {
        let authority = self.deletion_authority()?;
        DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .reconcile(&authority, true)
        .map_err(PrivateGroupError::Persistence)
    }
}
