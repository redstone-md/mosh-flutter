//! Retain verified own-state transitions before installing the next MLS state.
use super::*;
use crate::mls_crypto::{MlsHistoryContext, StagedMembership};
use crate::persistence::history_admission::EvidenceWrite;
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
struct NativeTransition {
    prior: MlsHistoryContext,
    next: MlsHistoryContext,
    original_author_mls_key: String,
    original_commit_b64: String,
    previous_member_keys: Vec<String>,
    next_member_keys: Vec<String>,
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
    let transition = NativeTransition {
        prior: staged.prior.clone(),
        next: staged.context.clone(),
        original_author_mls_key: hex::encode(&staged.author),
        original_commit_b64: encode(commit),
        previous_member_keys: previous.member_signers(),
        next_member_keys: staged.next.member_signers(),
        self_removed: staged.removed,
        original_signed_transition: None,
    };
    let evidence = EvidenceWrite {
        key: format!(
            "group/{}/transition/{:020}",
            hex::encode(Sha256::digest(group_id.as_bytes())),
            staged.prior.epoch
        ),
        bytes: serde_json::to_vec(&transition)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
    };
    store.commit_history_admission::<GroupMessage>(
        GROUP_HISTORY,
        group_id,
        HistoryAdmission {
            own_snapshot: Some(&staged.next.snapshot()),
            evidence: &[evidence],
            ..Default::default()
        },
        &[],
    )?;
    Ok(())
}
