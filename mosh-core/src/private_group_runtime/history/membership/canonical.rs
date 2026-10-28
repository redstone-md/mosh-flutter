//! Admission IDs come from the installation's verified MLS branch or pinned Welcome.
use super::*;

impl GroupSession {
    pub(in crate::private_group_runtime::history) fn canonical_membership(
        &self,
        context: &MlsHistoryContext,
        signer: &str,
    ) -> Result<Option<(MembershipReference, MlsHistoryContext)>, PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let prefix = format!(
            "group/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        );
        let mut cursor = context.clone();
        for _ in 0..4096 {
            if cursor.epoch == 0 {
                return Ok(Some((genesis_reference(&cursor, signer)?, cursor)));
            }
            let transition =
                store.group_history_evidence::<super::super::transitions::NativeTransition>(
                    &format!("{prefix}/transition/{:020}", cursor.epoch - 1),
                )?;
            let Some(transition) = transition else {
                return self.pinned_membership(&prefix, &cursor, signer);
            };
            if transition.next != cursor
                || !transition.next_member_keys.iter().any(|key| key == signer)
            {
                return Ok(None);
            }
            if !transition
                .previous_member_keys
                .iter()
                .any(|key| key == signer)
            {
                let commit = decode(&transition.original_commit_b64)?;
                return Ok(Some((
                    commit_reference(&cursor, &hex::encode(Sha256::digest(commit)), signer)?,
                    cursor,
                )));
            }
            cursor = transition.prior;
        }
        Ok(None)
    }

    fn pinned_membership(
        &self,
        prefix: &str,
        context: &MlsHistoryContext,
        signer: &str,
    ) -> Result<Option<(MembershipReference, MlsHistoryContext)>, PrivateGroupError> {
        let anchor =
            self.persistence
                .as_ref()
                .ok_or(PrivateGroupError::NotReady)?
                .group_history_evidence::<super::super::anchors::NativeAdmissionAnchor>(
                    &format!("{prefix}/evidence/admission-anchor/{}", context.hash),
                )?;
        anchor
            .filter(|anchor| anchor.context == *context && anchor.own_mls_key == signer)
            .and_then(|anchor| anchor.canonical_add_commit_hash)
            .map(|commit| {
                commit_reference(context, &commit, signer)
                    .map(|reference| (reference, context.clone()))
            })
            .transpose()
    }
}

fn commit_reference(
    context: &MlsHistoryContext,
    commit: &str,
    key: &str,
) -> Result<MembershipReference, PrivateGroupError> {
    Ok(MembershipReference::CommitV1(hash(
        b"mosh-history-admission-v1\0",
        &(1u8, hex::encode(&context.group_id), commit, key),
    )?))
}

fn genesis_reference(
    context: &MlsHistoryContext,
    key: &str,
) -> Result<MembershipReference, PrivateGroupError> {
    Ok(MembershipReference::GenesisV1(hash(
        b"mosh-history-genesis-v1\0",
        &(1u8, hex::encode(&context.group_id), &context.hash, key),
    )?))
}

fn hash<T: Serialize>(domain: &[u8], tuple: &T) -> Result<String, PrivateGroupError> {
    let mut hash = Sha256::new();
    hash.update(domain);
    hash.update(serde_json::to_vec(tuple).map_err(|e| PrivateGroupError::Codec(e.to_string()))?);
    Ok(hex::encode(hash.finalize()))
}
