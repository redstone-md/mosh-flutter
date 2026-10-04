//! Shared-name state belongs to the group; live authority is checked by its owner.
use super::*;
use crate::sender_auth::SenderProof;

mod cipher;
mod storage;
mod sync;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) enum NameOperation {
    Request,
    State,
    Ack,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct NameRevision {
    pub epoch: u64,
    pub roster_version: u64,
    pub counter: u64,
    pub actor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(super) struct NameChange {
    pub group_id: String,
    pub revision: NameRevision,
    pub name: String,
    pub from_device: String,
    pub sent_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct NameCertificate {
    pub change: NameChange,
    pub proof: Vec<u8>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub(crate) struct GroupNames {
    current: Option<NameCertificate>,
    previous: Option<NameCertificate>,
    previous_label: Option<String>,
    pub pending: bool,
    pub error: Option<String>,
}

impl PrivateGroupRuntime {
    pub fn rename_group(
        &mut self,
        id: &str,
        name: &str,
    ) -> Result<GroupSnapshot, PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(id)?;
        session.rename(name)?;
        Ok(session.snapshot())
    }
}

impl GroupSession {
    fn rename(&mut self, name: &str) -> Result<(), PrivateGroupError> {
        let name = crate::chat_names::validate_chat_name(name)
            .map_err(|e| PrivateGroupError::InvalidName(e.to_string()))?;
        if !self.joined || !self.crypto.is_ready() {
            return Err(PrivateGroupError::NotReady);
        }
        if !self.try_acting_admin()? {
            return Err(PrivateGroupError::RenameDenied);
        }
        if self.label.as_deref() == Some(&name) {
            return Ok(());
        }
        let counter = self
            .names
            .current
            .as_ref()
            .map(|c| c.change.revision.counter)
            .unwrap_or(0)
            .checked_add(1)
            .filter(|v| *v < u64::MAX)
            .ok_or(PrivateGroupError::NotReady)?;
        let change = NameChange {
            group_id: self.group_id.clone(),
            revision: NameRevision {
                epoch: self.crypto.epoch().ok_or(PrivateGroupError::NotReady)?,
                roster_version: self.own_roster_version().unwrap_or(0),
                counter,
                actor: hex::encode(self.crypto.signer_public()),
            },
            name,
            from_device: self.display_name.clone(),
            sent_at_ms: now_ms(),
        };
        let proof = self.sign_application(&change, &self.control_channel)?;
        let certificate = NameCertificate {
            change,
            proof: serde_json::to_vec(&proof)
                .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        };
        self.install_name(certificate, self.crypto.member_count() > 1)?;
        self.names_last_sync = None;
        Ok(())
    }
}
