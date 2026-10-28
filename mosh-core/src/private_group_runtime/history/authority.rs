//! Preserve original org authority separately from the ordinary history carrier.
use super::*;
use crate::mls_crypto::StagedMembership;
use crate::persistence::history_admission::EvidenceWrite;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct OriginalAuthority {
    org: String,
    mesh: String,
    signed: String,
    roster: String,
}

impl GroupSession {
    pub(in crate::private_group_runtime) fn retain_transition_authority(
        &mut self,
        envelope: &ControlEnvelope,
    ) -> Result<(), PrivateGroupError> {
        let Some(bytes) = self.incoming_org_control.as_deref() else {
            return Ok(());
        };
        let commit = match envelope {
            ControlEnvelope::Welcome { commit_b64, .. }
            | ControlEnvelope::Commit { commit_b64, .. } => decode(commit_b64)?,
            _ => return Ok(()),
        };
        let signed = bytes.to_vec();
        if self.org_pubkey.is_some() {
            self.org_roster_checked()?;
        }
        let Some(authority) = self.original_transition_authority(&signed) else {
            return Ok(());
        };
        if let Some(store) = &self.persistence {
            let prefix = pending_prefix(&self.group_id);
            store.save_pending_group_evidence(
                &prefix,
                &format!("{prefix}{}", hex::encode(Sha256::digest(commit))),
                &serde_json::to_vec(&authority)
                    .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
            )?;
        }
        Ok(())
    }

    pub(super) fn original_transition_authority(&self, signed: &[u8]) -> Option<OriginalAuthority> {
        Some(OriginalAuthority {
            org: self.org_pubkey.clone()?,
            mesh: self.mesh_id.clone(),
            signed: encode(signed),
            roster: encode(&self.roster_cache.as_ref()?.0),
        })
    }

    pub(super) fn verify_transition_authority(
        &mut self,
        transition: &super::transitions::NativeTransition,
        staged: &StagedMembership,
        raw: &[u8],
    ) -> Result<(), PrivateGroupError> {
        let Some(org) = self.org_pubkey.as_ref() else {
            return Ok(());
        };
        let authority = transition
            .original_signed_transition
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let authority: OriginalAuthority = decode_json(&decode(authority)?)?;
        if authority.org != *org || authority.mesh != self.mesh_id {
            return Err(PrivateGroupError::Codec(
                "original org transition scope differs".into(),
            ));
        }
        let original_version = authority.verify(&self.group_id, &self.crypto, staged, raw)?;
        if original_version > self.org_roster_checked()?.version {
            return Err(PrivateGroupError::NotReady);
        }
        Ok(())
    }
}

impl OriginalAuthority {
    pub(super) fn pinned(org: &str, mesh: &str, signed: &str, roster: &str) -> Self {
        Self {
            org: org.into(),
            mesh: mesh.into(),
            signed: signed.into(),
            roster: roster.into(),
        }
    }

    fn verify(
        &self,
        group: &str,
        previous: &MlsSessionCrypto,
        staged: &StagedMembership,
        raw: &[u8],
    ) -> Result<u64, PrivateGroupError> {
        let signed: OrgSigned = decode_json(&decode(&self.signed)?)?;
        org_envelope::verify(
            &signed,
            &OrgContext {
                org_pubkey: &self.org,
                mesh_id: &self.mesh,
                channel_kind: &format!("{CONTROL_CHANNEL_PREFIX}{group}"),
            },
        )
        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let roster = org_roster::verify(&decode(&self.roster)?, &self.org, None)
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let envelope: ControlEnvelope = decode_json(&signed.payload)?;
        let (actual_group, commit) = match envelope {
            ControlEnvelope::Commit {
                group_id,
                commit_b64,
                ..
            }
            | ControlEnvelope::Welcome {
                group_id,
                commit_b64,
                ..
            } => (group_id, decode(&commit_b64)?),
            _ => return Err(PrivateGroupError::NotReady),
        };
        if actual_group != group
            || commit != raw
            || previous
                .member_identity_for_signer(&staged.author)
                .as_deref()
                != Some(signed.peer_id.as_str())
            || !roster
                .members
                .iter()
                .any(|member| member.moss_peer_id == signed.peer_id && member.role == "admin")
        {
            return Err(PrivateGroupError::Codec(
                "original org commit authority differs".into(),
            ));
        }
        Ok(roster.version)
    }
}

pub(super) fn attach(
    mut write: EvidenceWrite,
    authority: Option<OriginalAuthority>,
) -> Result<EvidenceWrite, PrivateGroupError> {
    if let Some(authority) = authority {
        let mut transition: super::transitions::NativeTransition = decode_json(&write.bytes)?;
        transition.original_signed_transition = Some(encode(
            &serde_json::to_vec(&authority).map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        ));
        write.bytes =
            serde_json::to_vec(&transition).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
    }
    Ok(write)
}

pub(super) struct LiveAuthority {
    pub(super) original: OriginalAuthority,
    current_roster: Vec<u8>,
}

impl LiveAuthority {
    pub(super) fn guard(&self) -> crate::persistence::history_admission::OrgAuthorityGuard<'_> {
        crate::persistence::history_admission::OrgAuthorityGuard {
            org_key: &self.original.org,
            roster_bytes: &self.current_roster,
        }
    }
}

pub(super) fn retained(
    store: &Persistence,
    group: &str,
    previous: &MlsSessionCrypto,
    staged: &StagedMembership,
    raw: &[u8],
) -> Result<Option<LiveAuthority>, PrivateGroupError> {
    let key = format!(
        "{}{}",
        pending_prefix(group),
        hex::encode(Sha256::digest(raw))
    );
    let Some(mut original) = store.group_history_evidence::<OriginalAuthority>(&key)? else {
        return Ok(None);
    };
    let current_roster = store
        .get_org_roster(&original.org)?
        .ok_or(PrivateGroupError::NotReady)?;
    let roster = org_roster::verify(&current_roster, &original.org, None)
        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
    let author = previous.member_identity_for_signer(&staged.author);
    let own = previous.member_identity_for_signer(&previous.signer_public());
    if !roster
        .members
        .iter()
        .any(|member| Some(&member.moss_peer_id) == author.as_ref() && member.role == "admin")
        || !roster
            .members
            .iter()
            .any(|member| Some(&member.moss_peer_id) == own.as_ref())
    {
        return Err(PrivateGroupError::NotReady);
    }
    // A roster-lagged original frame becomes admissible only when its actual
    // author is admin in our newly verified roster. Retain that acceptance roster.
    if original.verify(group, previous, staged, raw).is_err() {
        original.roster = encode(&current_roster);
    }
    original.verify(group, previous, staged, raw)?;
    Ok(Some(LiveAuthority {
        original,
        current_roster,
    }))
}

fn pending_prefix(group: &str) -> String {
    format!(
        "group/{}/pending-transition/",
        hex::encode(Sha256::digest(group.as_bytes()))
    )
}
