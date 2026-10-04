use super::*;
use crate::sender_auth::VerifiedSender;
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize)]
enum NameMessage {
    Request,
    State(NameCertificate),
    Ack(NameRevision),
}

impl GroupSession {
    pub(crate) fn sync_names(&mut self) -> Result<(), PrivateGroupError> {
        if !self.joined || !self.crypto.is_ready() {
            return Ok(());
        }
        let is_admin = self.try_acting_admin()?;
        if self.names.pending && !is_admin {
            self.finish_pending_name(true)?;
        }
        if self.crypto.member_count() < 2 {
            return Ok(());
        }
        if self
            .names_last_sync
            .is_some_and(|t| t.elapsed() < Duration::from_secs(2))
        {
            return Ok(());
        }
        self.names_last_sync = Some(Instant::now());
        if is_admin {
            if let Some(certificate) = self.names.current.clone() {
                self.publish_name_message(NameOperation::State, &NameMessage::State(certificate))?;
            }
        }
        if !is_admin {
            self.publish_control(&ControlEnvelope::ResyncRequest {
                group_id: self.group_id.clone(),
                from_fingerprint: self.crypto.fingerprint(),
                have_epoch: self.crypto.epoch().unwrap_or_default(),
            })?;
        }
        self.publish_name_message(NameOperation::Request, &NameMessage::Request)
    }

    fn publish_name_message(
        &mut self,
        operation: NameOperation,
        message: &NameMessage,
    ) -> Result<(), PrivateGroupError> {
        let envelope = self.name_envelope(operation, message)?;
        self.publish_control(&envelope)
    }

    fn name_envelope(
        &mut self,
        operation: NameOperation,
        message: &NameMessage,
    ) -> Result<ControlEnvelope, PrivateGroupError> {
        Ok(ControlEnvelope::NameMetadata {
            group_id: self.group_id.clone(),
            operation,
            epoch: self.crypto.epoch().ok_or(PrivateGroupError::NotReady)?,
            ciphertext_b64: self.seal_name(message)?,
        })
    }

    pub(crate) fn name_handoff_proof(&mut self) -> Result<Option<String>, PrivateGroupError> {
        if !self.acting_admin() {
            return Ok(None);
        }
        let Some(certificate) = self.names.current.clone() else {
            return Ok(None);
        };
        let envelope =
            self.name_envelope(NameOperation::State, &NameMessage::State(certificate))?;
        let proof = self.sign_application(&envelope, &self.control_channel)?;
        let bytes =
            serde_json::to_vec(&proof).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        Ok(Some(encode(&bytes)))
    }

    pub(crate) fn accept_name_metadata(
        &mut self,
        operation: NameOperation,
        epoch: u64,
        ciphertext: &str,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        if sender.mls_signer == self.crypto.signer_public() {
            return Ok(());
        }
        // Check current authority before opening shared-name state.
        if operation == NameOperation::State && !self.name_admin(&sender) {
            return Err(PrivateGroupError::RenameDenied);
        }
        let message: NameMessage = decode_json(&self.open_name(epoch, ciphertext)?)?;
        match (operation, message) {
            (NameOperation::Request, NameMessage::Request) if self.acting_admin() => {
                if let Some(certificate) = self.names.current.clone() {
                    self.publish_name_message(
                        NameOperation::State,
                        &NameMessage::State(certificate),
                    )?;
                }
            }
            (NameOperation::State, NameMessage::State(certificate)) => {
                self.accept_name_state(certificate)?;
            }
            (NameOperation::Ack, NameMessage::Ack(revision)) => {
                if self.names.pending
                    && self
                        .names
                        .current
                        .as_ref()
                        .is_some_and(|c| c.change.revision == revision)
                {
                    let rejected = !self.try_acting_admin()?;
                    self.finish_pending_name(rejected)?;
                }
            }
            (NameOperation::Request, NameMessage::Request) => {}
            _ => return Err(PrivateGroupError::Codec("name operation mismatch".into())),
        }
        Ok(())
    }

    fn name_admin(&mut self, sender: &VerifiedSender) -> bool {
        if self.org_pubkey.is_some() {
            return self.roster_role_is_admin(&sender.peer_id);
        }
        hex::encode_upper(&sender.mls_signer).starts_with(&self.current_admin_fingerprint)
    }

    fn accept_name_state(&mut self, certificate: NameCertificate) -> Result<(), PrivateGroupError> {
        let revision = certificate.change.revision.clone();
        if revision.epoch > self.crypto.epoch().unwrap_or_default()
            || revision.roster_version > self.own_roster_version().unwrap_or_default()
        {
            return Err(PrivateGroupError::NotReady);
        }
        let previous = self.names.current.as_ref();
        if previous.is_some_and(|c| c.change.revision == revision && c.change != certificate.change)
        {
            return Err(PrivateGroupError::Codec(
                "conflicting name certificate".into(),
            ));
        }
        if previous.is_none_or(|c| c.change.revision < revision) {
            self.install_name(certificate, false)?;
            self.names_last_sync = None;
        }
        if self
            .names
            .current
            .as_ref()
            .is_some_and(|c| c.change.revision == revision)
        {
            self.publish_name_message(NameOperation::Ack, &NameMessage::Ack(revision))?;
        }
        Ok(())
    }
}
