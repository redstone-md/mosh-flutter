//! Missing encrypted commits are replayed through our own MlsGroup, one bounded record at a time.
use super::protocol::{CheckedFrame, CurrentHead, GroupBody, GroupScope};
use super::*;
use crate::conversation::recovery::{
    fragment::{self, PageFragment, PartialRecord},
    wire::{HistoryFrame, HistoryMessage},
};
use crate::mls_crypto::MlsHistoryContext;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(super) enum EvidenceMessage {
    Pull {
        have: MlsHistoryContext,
        target: CurrentHead,
        offset: usize,
    },
    Page {
        have: MlsHistoryContext,
        target: CurrentHead,
        fragment: PageFragment,
    },
}

#[derive(Serialize, Deserialize)]
struct EvidenceTransfer {
    source: String,
    have: MlsHistoryContext,
    target: CurrentHead,
    partial: Option<PartialRecord>,
}

impl GroupSession {
    pub(super) fn request_transition_evidence(
        &mut self,
        frame: &HistoryFrame,
        remote: &GroupScope,
    ) -> Result<(), PrivateGroupError> {
        let have = self.crypto.history_context()?;
        if remote.head.context.group_id != have.group_id
            || remote.head.context.epoch <= have.epoch
            || remote.head.context.epoch.saturating_sub(have.epoch) > 4096
        {
            return Err(PrivateGroupError::Codec(
                "history head cannot replace our branch".into(),
            ));
        }
        let state = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_state::<EvidenceTransfer>(&self.evidence_transfer_key(&frame.sender_key))?
            .filter(|saved| {
                saved.have == have
                    && saved.target == remote.head
                    && saved.source == frame.sender_key
            });
        let offset = state
            .and_then(|saved| saved.partial)
            .map_or(0, |partial| partial.offset());
        self.send_transition_evidence(
            frame,
            EvidenceMessage::Pull {
                have,
                target: remote.head.clone(),
                offset,
            },
        )
    }

    pub(super) fn receive_transition_evidence(
        &mut self,
        checked: CheckedFrame,
    ) -> Result<(), PrivateGroupError> {
        let message = checked
            .body
            .evidence
            .clone()
            .ok_or(PrivateGroupError::NotReady)?;
        match message {
            EvidenceMessage::Pull {
                have,
                target,
                offset,
            } => {
                if target != self.current_history_head()?
                    || have.group_id != target.context.group_id
                    || have.epoch >= target.context.epoch
                    || target.context.epoch - have.epoch > 4096
                {
                    return Err(PrivateGroupError::Codec(
                        "evidence pull head differs".into(),
                    ));
                }
                let store = self
                    .persistence
                    .as_ref()
                    .ok_or(PrivateGroupError::NotReady)?;
                let transition = store
                    .group_history_evidence::<super::transitions::NativeTransition>(&format!(
                        "group/{}/transition/{:020}",
                        hex::encode(Sha256::digest(self.group_id.as_bytes())),
                        have.epoch
                    ))?
                    .filter(|transition| transition.prior == have)
                    .ok_or(PrivateGroupError::NotReady)?;
                let bytes = serde_json::to_vec(&transition)
                    .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
                self.send_transition_evidence(
                    &checked.frame,
                    EvidenceMessage::Page {
                        have,
                        target,
                        fragment: fragment::fragment(&bytes, offset)
                            .map_err(PrivateGroupError::Codec)?,
                    },
                )
            }
            EvidenceMessage::Page {
                have,
                target,
                fragment,
            } => {
                if self.crypto.history_context()? != have
                    || checked.body.scope.head != target
                    || target.context.group_id != have.group_id
                    || target.context.epoch <= have.epoch
                    || target.context.epoch.saturating_sub(have.epoch) > 4096
                {
                    return Err(PrivateGroupError::Codec(
                        "evidence page cursor differs".into(),
                    ));
                }
                self.accept_transition_fragment(&checked.frame, have, target, fragment)
            }
        }
    }

    fn accept_transition_fragment(
        &mut self,
        frame: &HistoryFrame,
        have: MlsHistoryContext,
        target: CurrentHead,
        fragment: PageFragment,
    ) -> Result<(), PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .clone();
        let key = self.evidence_transfer_key(&frame.sender_key);
        let mut state = store
            .recovery_state::<EvidenceTransfer>(&key)?
            .filter(|saved| {
                saved.have == have && saved.target == target && saved.source == frame.sender_key
            })
            .unwrap_or(EvidenceTransfer {
                source: frame.sender_key.clone(),
                have: have.clone(),
                target: target.clone(),
                partial: None,
            });
        let complete = PartialRecord::accept(&mut state.partial, fragment)
            .map_err(PrivateGroupError::Codec)?;
        if let Some(bytes) = complete {
            self.install_transition_evidence(&have, &target, &bytes, &key)?;
        } else {
            store.save_recovery(&key, &state)?;
        }
        let current = self.crypto.history_context()?;
        if current != target.context {
            self.send_transition_evidence(
                frame,
                EvidenceMessage::Pull {
                    have: current,
                    target,
                    offset: state.partial.as_ref().map_or(0, |partial| partial.offset()),
                },
            )?;
        }
        Ok(())
    }

    pub(in crate::private_group_runtime) fn install_transition_evidence(
        &mut self,
        have: &MlsHistoryContext,
        target: &CurrentHead,
        bytes: &[u8],
        partial_key: &str,
    ) -> Result<(), PrivateGroupError> {
        let transition: super::transitions::NativeTransition = decode_json(bytes)?;
        let raw = decode(&transition.original_commit_b64)?;
        let staged = self.crypto.stage_membership(&raw, None)?;
        if staged.prior != *have
            || transition.prior != staged.prior
            || transition.next != staged.context
            || staged.context.epoch > target.context.epoch
            || (staged.context.epoch == target.context.epoch && staged.context != target.context)
            || staged.removed
        {
            return Err(PrivateGroupError::Codec(
                "evidence commit differs from own branch".into(),
            ));
        }
        self.verify_transition_authority(&transition, &staged, &raw)?;
        let store = self
            .persistence
            .clone()
            .ok_or(PrivateGroupError::NotReady)?;
        let evidence = super::transitions::transition_write(
            super::transitions::TransitionState {
                previous: &self.crypto,
                next: &staged.next,
                prior: &staged.prior,
                context: &staged.context,
                author: &staged.author,
                removed: staged.removed,
            },
            &self.group_id,
            &raw,
        )?;
        let evidence = super::authority::attach(
            evidence,
            transition
                .original_signed_transition
                .as_ref()
                .map(|value| {
                    decode(value)
                        .map_err(PrivateGroupError::from)
                        .and_then(|bytes| decode_json(&bytes))
                })
                .transpose()?,
        )?;
        let mut head = self.current_history_head()?;
        head.context = staged.context.clone();
        let checkpoint = serde_json::to_vec(&super::recovery::GroupCheckpoint {
            checkpoint: Default::default(),
            head: head.clone(),
        })
        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let key = self.checkpoint_key();
        store.commit_history_admission::<GroupMessage>(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                own_snapshot: Some(&staged.next.snapshot()),
                evidence: &[evidence],
                checkpoint: Some((&key, &checkpoint)),
                remove_recovery_prefix: partial_key.strip_suffix("\u{1}state"),
                org_authority: self.org_history_guard(&self.device_fingerprint, false)?,
                ..Default::default()
            },
            &[],
        )?;
        self.crypto = staged.next;
        self.recovery = Default::default();
        self.history_head = Some(head);
        self.history_dispatch.invalidate();
        self.reconcile_admin();
        self.needs_rejoin = false;
        Ok(())
    }

    fn send_transition_evidence(
        &mut self,
        frame: &HistoryFrame,
        evidence: EvidenceMessage,
    ) -> Result<(), PrivateGroupError> {
        let scope = self.own_history_scope()?;
        self.dispatch_history_body(
            Some(frame.sender_key.clone()),
            frame.request_id.clone(),
            frame.round,
            GroupBody {
                scope,
                message: HistoryMessage::Unavailable,
                evidence: Some(evidence),
                partial_digest: None,
                erased_fragment: false,
            },
            self.history_dispatch.permit(),
        )
    }

    fn evidence_transfer_key(&self, _peer: &str) -> String {
        format!("{}\u{1}evidence-transfer\u{1}state", self.checkpoint_key())
    }
}
