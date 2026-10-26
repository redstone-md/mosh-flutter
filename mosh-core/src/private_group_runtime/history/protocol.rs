//! Group-only permission metadata stays inside the existing signed history frame.
use super::membership::NativeCheckpoint;
use super::*;
use crate::conversation::recovery::{
    transport::DispatchPermit,
    wire::{HistoryFrame, HistoryMessage},
};
use crate::mls_crypto::MlsHistoryContext;
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::private_group_runtime) struct CurrentHead {
    pub(in crate::private_group_runtime) context: MlsHistoryContext,
    pub(in crate::private_group_runtime) org_roster_version: Option<u64>,
    pub(in crate::private_group_runtime) org_roster_hash: Option<String>,
}
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct GroupScope {
    pub(super) head: CurrentHead,
    pub(super) membership: NativeCheckpoint,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) previous_memberships: Vec<NativeCheckpoint>,
}
#[derive(Serialize, Deserialize)]
pub(super) struct GroupBody {
    pub(super) scope: GroupScope,
    pub(super) message: HistoryMessage<super::records::GroupRecord>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) evidence: Option<super::transition_exchange::EvidenceMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) partial_digest: Option<String>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub(super) erased_fragment: bool,
}
#[derive(Serialize, Deserialize)]
pub(super) struct DirectedHistory {
    pub(super) group_id: String,
    pub(super) proof: crate::sender_auth::SenderProof,
}

impl GroupSession {
    pub(super) fn current_history_head(&mut self) -> Result<CurrentHead, PrivateGroupError> {
        let context = self.crypto.history_context()?;
        let roster = self
            .org_pubkey
            .as_ref()
            .map(|_| ())
            .map(|_| self.org_roster_checked())
            .transpose()?;
        let roster_hash = roster
            .as_ref()
            .map(|_| {
                self.roster_cache
                    .as_ref()
                    .map(|cache| hex::encode(Sha256::digest(&cache.0)))
                    .ok_or(PrivateGroupError::NotReady)
            })
            .transpose()?;
        Ok(CurrentHead {
            context,
            org_roster_version: roster.as_ref().map(|r| r.version),
            org_roster_hash: roster_hash,
        })
    }

    pub(super) fn own_history_scope(&mut self) -> Result<GroupScope, PrivateGroupError> {
        let context = self.crypto.history_context()?;
        let checkpoint = if let Some((_, checkpoint)) = self
            .history_membership
            .as_ref()
            .filter(|(head, _)| *head == context)
        {
            checkpoint.clone()
        } else {
            self.persist_own_history_membership(&context)?
        };
        let previous_memberships = self.previous_history_memberships(&checkpoint)?;
        let scope = GroupScope {
            head: self.current_history_head()?,
            membership: checkpoint,
            previous_memberships,
        };
        if serde_json::to_vec(&scope)
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?
            .len()
            > 20_000
        {
            return Err(PrivateGroupError::Codec(
                "group interval proof budget exceeded".into(),
            ));
        }
        Ok(scope)
    }

    fn persist_own_history_membership(
        &mut self,
        context: &MlsHistoryContext,
    ) -> Result<NativeCheckpoint, PrivateGroupError> {
        let own = self.own_history_membership()?;
        if !own.writes.is_empty() {
            let store = self
                .persistence
                .as_deref()
                .ok_or(PrivateGroupError::NotReady)?;
            store.commit_history_admission::<GroupMessage>(
                GROUP_HISTORY,
                &self.group_id,
                HistoryAdmission {
                    org_authority: self.org_history_guard(&self.device_fingerprint, false)?,
                    evidence: &own.writes,
                    ..Default::default()
                },
                &[],
            )?;
        }
        self.history_membership = Some((context.clone(), own.checkpoint.clone()));
        Ok(own.checkpoint)
    }

    pub(super) fn validate_history_scope(
        &mut self,
        scope: &GroupScope,
        peer: &str,
    ) -> Result<crate::sender_auth::VerifiedSender, PrivateGroupError> {
        if scope.head != self.current_history_head()? {
            return Err(PrivateGroupError::Codec(
                "history requires membership evidence".into(),
            ));
        }
        let member = scope.membership.verify_current(self)?;
        if member.peer_id != peer {
            return Err(PrivateGroupError::Codec(
                "history carrier membership differs".into(),
            ));
        }
        Ok(member)
    }
}

pub(super) struct CheckedFrame {
    pub(super) frame: HistoryFrame,
    pub(super) body: GroupBody,
    pub(super) sender: crate::sender_auth::VerifiedSender,
    pub(super) permit: DispatchPermit,
}
