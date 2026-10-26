//! Pinned own admission anchors, distinct from unverified outer commit hints.
use super::*;
use crate::mls_crypto::{MlsHistoryContext, StagedAdmission};
use crate::persistence::history_admission::{EvidenceWrite, OrgAuthorityGuard};
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
struct NativeAdmissionAnchor {
    context: MlsHistoryContext,
    original_author_mls_key: String,
    original_author_identity: String,
    own_mls_key: String,
    original_welcome_b64: String,
    original_tree_b64: String,
    canonical_add_commit_hash: Option<String>,
    original_org_signed_b64: Option<String>,
    original_org_roster_b64: Option<String>,
}

impl GroupSession {
    pub(super) fn org_history_guard(
        &self,
        author: &str,
        require_admin: bool,
    ) -> Result<Option<OrgAuthorityGuard<'_>>, PrivateGroupError> {
        let Some(org_key) = self.org_pubkey.as_deref() else {
            return Ok(None);
        };
        let (bytes, roster) = self
            .roster_cache
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let own = self.own_peer_id();
        let permitted = roster.members.iter().any(|member| {
            member.moss_peer_id == author && (!require_admin || member.role == "admin")
        });
        if !permitted
            || !roster
                .members
                .iter()
                .any(|member| Some(member.moss_peer_id.as_str()) == own.as_deref())
        {
            return Err(PrivateGroupError::NotReady);
        }
        Ok(Some(OrgAuthorityGuard {
            org_key,
            roster_bytes: bytes,
        }))
    }

    pub(in crate::private_group_runtime) fn persist_pinned_admission(
        &self,
        staged: &StagedAdmission,
        welcome_b64: &str,
        tree_b64: &str,
        commit_b64: &str,
    ) -> Result<(), PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let authority = self.org_history_guard(&staged.author_identity, true)?;
        let anchor = NativeAdmissionAnchor {
            context: staged.context.clone(),
            original_author_mls_key: hex::encode(&staged.author),
            original_author_identity: staged.author_identity.clone(),
            own_mls_key: hex::encode(staged.next.signer_public()),
            original_welcome_b64: welcome_b64.into(),
            original_tree_b64: tree_b64.into(),
            canonical_add_commit_hash: self.original_org_add_hash(staged, commit_b64)?,
            original_org_signed_b64: self
                .incoming_org_control
                .as_ref()
                .map(|bytes| encode(bytes)),
            original_org_roster_b64: authority.as_ref().map(|guard| encode(guard.roster_bytes)),
        };
        self.commit_pinned_anchor(staged, &anchor, authority, store)
    }

    fn original_org_add_hash(
        &self,
        staged: &StagedAdmission,
        commit_b64: &str,
    ) -> Result<Option<String>, PrivateGroupError> {
        if self.org_pubkey.is_none() || self.incoming_org_control.is_none() {
            return Ok(None);
        }
        // The already-verified original OrgSigned payload covers this exact
        // Welcome/commit pair. Its sender equals the staged GroupInfo author.
        // This is an original issuer association, not prejoin commit replay.
        let commit = decode(commit_b64)?;
        let (group, epoch) = MlsSessionCrypto::admission_commit_header(&commit)?;
        if group != staged.context.group_id || epoch.checked_add(1) != Some(staged.context.epoch) {
            return Err(PrivateGroupError::Codec(
                "org admission commit association mismatch".into(),
            ));
        }
        Ok(Some(hex::encode(Sha256::digest(commit))))
    }

    fn commit_pinned_anchor(
        &self,
        staged: &StagedAdmission,
        anchor: &NativeAdmissionAnchor,
        authority: Option<OrgAuthorityGuard<'_>>,
        store: &Persistence,
    ) -> Result<(), PrivateGroupError> {
        let mut record = self.to_persisted_record();
        record.joined = true;
        record.signer_public = staged.next.signer_public();
        record.mls_group_id = staged.context.group_id.clone();
        let record = serde_json::to_vec(&record)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        let evidence = EvidenceWrite {
            key: format!(
                "group/{}/evidence/admission-anchor/{}",
                hex::encode(Sha256::digest(self.group_id.as_bytes())),
                staged.context.hash
            ),
            bytes: serde_json::to_vec(anchor)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
        };
        store.commit_history_admission::<GroupMessage>(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                state: Some((&self.group_id, &record)),
                own_snapshot: Some(&staged.next.snapshot()),
                finalize_native: true,
                org_authority: authority,
                evidence: &[evidence],
                ..Default::default()
            },
            &[],
        )?;
        Ok(())
    }
}
