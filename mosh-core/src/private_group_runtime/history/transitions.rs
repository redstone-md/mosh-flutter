//! Retain verified own-state transitions before installing the next MLS state.
use super::*;
use crate::mls_crypto::{MlsHistoryContext, StagedMembership};
use crate::persistence::history_admission::EvidenceWrite;
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
pub(super) struct NativeTransition {
    pub(super) prior: MlsHistoryContext,
    pub(super) next: MlsHistoryContext,
    original_author_mls_key: String,
    original_commit_b64: String,
    pub(super) previous_member_keys: Vec<String>,
    pub(super) next_member_keys: Vec<String>,
    self_removed: bool,
    // Native replay proves the own branch. Missing original org/dual-key
    // transition evidence stays unavailable to remote history verification.
    original_signed_transition: Option<String>,
}

pub(in crate::private_group_runtime) fn persist_membership(
    previous: &MlsSessionCrypto,
    staged: &StagedMembership,
    store: Option<&Persistence>,
    group_id: &str,
    commit: &[u8],
) -> Result<(), PrivateGroupError> {
    let Some(store) = store else {
        return Ok(());
    };
    let evidence = transition_write(
        TransitionState {
            previous,
            next: &staged.next,
            prior: &staged.prior,
            context: &staged.context,
            author: &staged.author,
            removed: staged.removed,
        },
        group_id,
        commit,
    )?;
    let mut evidence = vec![evidence];
    evidence.extend(super::admission_commit::verified_association(
        store, group_id, previous, staged, commit,
    )?);
    store.commit_history_admission::<GroupMessage>(
        GROUP_HISTORY,
        group_id,
        HistoryAdmission {
            own_snapshot: Some(&staged.next.snapshot()),
            evidence: &evidence,
            ..Default::default()
        },
        &[],
    )?;
    Ok(())
}

pub(super) struct TransitionState<'a> {
    pub(super) previous: &'a MlsSessionCrypto,
    pub(super) next: &'a MlsSessionCrypto,
    pub(super) prior: &'a MlsHistoryContext,
    pub(super) context: &'a MlsHistoryContext,
    pub(super) author: &'a [u8],
    pub(super) removed: bool,
}

pub(super) fn transition_write(
    state: TransitionState<'_>,
    group: &str,
    commit: &[u8],
) -> Result<EvidenceWrite, PrivateGroupError> {
    let TransitionState {
        previous,
        next,
        prior,
        context,
        author,
        removed,
    } = state;
    let transition = NativeTransition {
        prior: prior.clone(),
        next: context.clone(),
        original_author_mls_key: hex::encode(author),
        original_commit_b64: encode(commit),
        previous_member_keys: previous.member_signers(),
        next_member_keys: next.member_signers(),
        self_removed: removed,
        original_signed_transition: None,
    };
    Ok(EvidenceWrite {
        key: format!(
            "group/{}/transition/{:020}",
            hex::encode(Sha256::digest(group.as_bytes())),
            prior.epoch
        ),
        bytes: serde_json::to_vec(&transition)
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
    })
}
