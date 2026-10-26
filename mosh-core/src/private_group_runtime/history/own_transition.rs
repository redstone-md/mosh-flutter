//! Own removals use the same durable transition boundary as received commits.
use super::*;

impl GroupSession {
    pub(in crate::private_group_runtime) fn publish_membership_change(
        &mut self,
        candidate: MlsSessionCrypto,
        raw: Vec<u8>,
    ) -> Result<(), PrivateGroupError> {
        let prior = self.crypto.history_context()?;
        let context = candidate.history_context()?;
        let envelope = ControlEnvelope::Commit {
            group_id: self.group_id.clone(),
            from_fingerprint: self.crypto.fingerprint(),
            commit_b64: encode(&raw),
            roster_version: self.own_roster_version(),
            admission_binding: None,
        };
        let bytes = super::super::wires::control_payload(
            &self.control_channel,
            &self.mesh_id,
            org_context(self.org_pubkey.as_deref(), self.org_signer.as_ref()),
            &envelope,
        )?;
        if let Some(store) = self.persistence.as_ref() {
            let evidence = super::transitions::transition_write(
                super::transitions::TransitionState {
                    previous: &self.crypto,
                    next: &candidate,
                    prior: &prior,
                    context: &context,
                    author: &self.crypto.signer_public(),
                    removed: false,
                },
                &self.group_id,
                &raw,
            )?;
            let evidence =
                super::authority::attach(evidence, self.original_transition_authority(&bytes))?;
            store.commit_history_admission::<GroupMessage>(
                GROUP_HISTORY,
                &self.group_id,
                HistoryAdmission {
                    own_snapshot: Some(&candidate.snapshot()),
                    evidence: &[evidence],
                    org_authority: self.org_history_guard(&self.device_fingerprint, true)?,
                    ..Default::default()
                },
                &[],
            )?;
        }
        self.crypto = candidate;
        self.log_commit(prior.epoch, &raw);
        self.node
            .publish_room_best_effort(&self.mesh_id, &self.control_channel, &bytes)
            .map_err(|e| PrivateGroupError::Moss(e.to_string()))
    }
}
