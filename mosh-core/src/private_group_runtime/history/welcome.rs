//! Replaying the same join request retransmits its original accepted admission.
use super::*;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::SenderProof;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(in crate::private_group_runtime) struct AdmissionReplay {
    welcome: Vec<u8>,
    commit: Vec<u8>,
}

impl GroupSession {
    pub(in crate::private_group_runtime) fn prepare_admission_replay(
        &mut self,
        outcome: &AddOutcome,
        participant: String,
        author: String,
        binding: SenderProof,
    ) -> Result<AdmissionReplay, PrivateGroupError> {
        let welcome = ControlEnvelope::Welcome {
            group_id: self.group_id.clone(),
            for_participant_id: participant,
            from_fingerprint: author.clone(),
            welcome_b64: encode(&outcome.welcome_bytes),
            tree_b64: encode(&outcome.tree_bytes),
            commit_b64: encode(&outcome.commit_bytes),
            admission_binding: Some(binding.clone()),
        };
        let commit = ControlEnvelope::Commit {
            group_id: self.group_id.clone(),
            from_fingerprint: author,
            commit_b64: encode(&outcome.commit_bytes),
            roster_version: self.own_roster_version(),
            admission_binding: Some(binding),
        };
        let payload = |value| {
            super::super::wires::control_payload(
                &self.control_channel,
                &self.mesh_id,
                org_context(self.org_pubkey.as_deref(), self.org_signer.as_ref()),
                value,
            )
        };
        Ok(AdmissionReplay {
            welcome: payload(&welcome)?,
            commit: payload(&commit)?,
        })
    }

    pub(in crate::private_group_runtime) fn admission_replay_key(&self, package: &[u8]) -> String {
        format!(
            "group/{}/admission-replay/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes())),
            hex::encode(Sha256::digest(package))
        )
    }

    pub(in crate::private_group_runtime) fn retain_admission_replay(
        &mut self,
        key: String,
        replay: AdmissionReplay,
    ) {
        // A persistence-free runtime has the same retry behavior with bounded RAM.
        if self.admission_replays.len() >= 32 {
            self.admission_replays.pop_first();
        }
        self.admission_replays.insert(key, replay);
    }

    pub(in crate::private_group_runtime) fn replay_admission(
        &self,
        package: &[u8],
    ) -> Result<(), PrivateGroupError> {
        let key = self.admission_replay_key(package);
        let saved = self
            .persistence
            .as_ref()
            .map(|store| store.group_history_evidence::<AdmissionReplay>(&key))
            .transpose()?
            .flatten();
        if let Some(saved) = saved.as_ref().or_else(|| self.admission_replays.get(&key)) {
            self.publish_admission_replay(saved)?;
        }
        Ok(())
    }

    pub(in crate::private_group_runtime) fn publish_admission_replay(
        &self,
        saved: &AdmissionReplay,
    ) -> Result<(), PrivateGroupError> {
        for bytes in [&saved.welcome, &saved.commit] {
            self.node
                .publish_room_best_effort(&self.mesh_id, &self.control_channel, bytes)
                .map_err(|error| PrivateGroupError::Moss(error.to_string()))?;
        }
        Ok(())
    }
}

pub(super) fn replay_write(
    key: &str,
    replay: &AdmissionReplay,
) -> Result<EvidenceWrite, PrivateGroupError> {
    Ok(EvidenceWrite {
        key: key.into(),
        bytes: serde_json::to_vec(replay)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
    })
}
