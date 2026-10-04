//! The control channel handlers.

use super::*;

#[cfg(test)]
#[path = "manifest_author_tests.rs"]
mod manifest_author_tests;

impl GroupSession {
    pub(super) fn handle_control(
        &mut self,
        payload: Vec<u8>,
        sender_peer_id: Option<String>,
    ) -> Result<(), PrivateGroupError> {
        if let Ok(proof) = serde_json::from_slice::<crate::sender_auth::SenderProof>(&payload) {
            return self.handle_authenticated_control(proof);
        }
        let envelope: ControlEnvelope = decode_json(&payload)?;
        // Admission stays compatible with existing MLS trees. Application
        // traffic without a sender proof is never admitted, even after Welcome.
        if envelope.is_application() {
            return Ok(());
        }
        if envelope.group_id() != self.group_id {
            return Ok(());
        }
        let own_fp = self.crypto.fingerprint();
        self.handle_admission_control(envelope, sender_peer_id.as_deref(), own_fp)
    }

    fn handle_admission_control(
        &mut self,
        envelope: ControlEnvelope,
        sender: Option<&str>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        match envelope {
            ControlEnvelope::KeyPackage {
                participant_id,
                key_package_b64,
                ..
            } if self.participant_id != participant_id => {
                self.accept_key_package(participant_id, &key_package_b64, sender, own_fp)
            }
            ControlEnvelope::Welcome {
                for_participant_id,
                from_fingerprint,
                welcome_b64,
                tree_b64,
                commit_b64,
                ..
            } if !self.joined && !self.is_admin && self.participant_id == for_participant_id => {
                self.accept_welcome(
                    &from_fingerprint,
                    &welcome_b64,
                    &tree_b64,
                    commit_b64,
                    sender,
                )
            }
            ControlEnvelope::Welcome {
                from_fingerprint,
                commit_b64,
                ..
            } if self.joined && !self.is_admin => {
                self.accept_admission_commit(&from_fingerprint, commit_b64, sender)
            }
            other => self.handle_membership_control(other, sender, own_fp),
        }
    }

    fn handle_membership_control(
        &mut self,
        envelope: ControlEnvelope,
        sender: Option<&str>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        match envelope {
            ControlEnvelope::Commit {
                from_fingerprint,
                commit_b64,
                roster_version,
                ..
            } if self.joined => {
                self.accept_commit(from_fingerprint, commit_b64, roster_version, sender, own_fp)
            }
            ControlEnvelope::SelfRemove {
                from_fingerprint,
                proposal_b64,
                name_state_proof_b64,
                ..
            } if from_fingerprint != own_fp => self.accept_departure(
                &from_fingerprint,
                &proposal_b64,
                name_state_proof_b64,
                own_fp,
            ),
            ControlEnvelope::ResyncRequest {
                from_fingerprint,
                have_epoch,
                ..
            } if from_fingerprint != own_fp => {
                self.accept_resync_request(from_fingerprint, have_epoch, sender)
            }
            ControlEnvelope::ResyncResponse {
                for_fingerprint,
                commits,
                ..
            } if self.joined && for_fingerprint == own_fp => {
                self.accept_resync_response(commits, sender)
            }
            _ => Ok(()),
        }
    }

    fn accept_key_package(
        &mut self,
        participant_id: String,
        key_package_b64: &str,
        sender: Option<&str>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        if !self.acting_admin() {
            return Ok(());
        }
        let key_package = decode(key_package_b64)?;
        // Drop replays / rogue duplicate admit attempts whose MLS
        // signer is already covered by the roster.
        if self.crypto.key_package_signer_is_member(&key_package)? {
            return Ok(());
        }
        if self.org_pubkey.is_some() {
            return self.admit_org_member(sender, participant_id, &key_package, own_fp);
        }
        let pre_epoch = self.crypto.epoch();
        let outcome = self.crypto.add_members(&[key_package.as_slice()])?;
        self.broadcast_admission(pre_epoch, &outcome, participant_id, own_fp)
    }
    fn accept_welcome(
        &mut self,
        from_fingerprint: &str,
        welcome_b64: &str,
        tree_b64: &str,
        commit_b64: String,
        sender: Option<&str>,
    ) -> Result<(), PrivateGroupError> {
        if !self.commit_author_authorized(from_fingerprint, sender) {
            return Ok(());
        }
        self.crypto.join_welcome_pinned(
            &decode(welcome_b64)?,
            &decode(tree_b64)?,
            from_fingerprint,
            None,
            self.org_pubkey.as_ref().and(sender),
        )?;
        self.joined = true;
        self.pending_join_package = None;
        // The Welcome already carries the admission commit's state. The
        // admin also broadcasts that same commit on the control channel
        // for existing members, so mark it processed to skip re-applying
        // it to ourselves (which would error on the already-merged epoch).
        self.sequencer.mark_seen(commit_b64);
        Ok(())
    }
    fn accept_admission_commit(
        &mut self,
        from_fingerprint: &str,
        commit_b64: String,
        sender: Option<&str>,
    ) -> Result<(), PrivateGroupError> {
        if !self.commit_author_authorized(from_fingerprint, sender) {
            return Ok(());
        }
        self.apply_commit_sequenced(commit_b64)
    }
    fn accept_commit(
        &mut self,
        from_fingerprint: String,
        commit_b64: String,
        roster_version: Option<u64>,
        sender: Option<&str>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        if self.org_pubkey.is_some() {
            // Roster-derived authority incl. the lag buffer; own
            // commits come back around but dedup as already-applied.
            self.apply_org_commit(commit_b64, roster_version, sender)
        } else if from_fingerprint == own_fp {
            // Our own echo; already merged when we authored it.
            Ok(())
        } else {
            // Plain groups: MLS and the epoch sequencer are the
            // authority. `from_fingerprint` is a self-claim on an
            // unauthenticated channel, so gating on it stopped no
            // attacker — it only froze members whose admin pointer
            // was stale, and the successor's departure commit is
            // authored by a non-admin by design (ADR 0023).
            self.apply_commit_sequenced(commit_b64)
        }
    }
    fn accept_departure(
        &mut self,
        from_fingerprint: &str,
        proposal_b64: &str,
        name_state_proof_b64: Option<String>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        if let Some(encoded) = name_state_proof_b64 {
            // A bad optional handoff must not prevent a valid MLS departure.
            let handoff = decode(&encoded)
                .map_err(PrivateGroupError::from)
                .and_then(|bytes| decode_json(&bytes))
                .and_then(|proof| self.handle_authenticated_control(proof));
            if let Err(error @ PrivateGroupError::Persistence(_)) = handoff {
                return Err(error);
            }
        }
        if !self.should_commit_departure(from_fingerprint) {
            return Ok(());
        }
        let proposal = decode(proposal_b64)?;
        let pre_epoch = self.crypto.epoch();
        let commit_bytes = self.crypto.commit_departure(&proposal)?;
        if let Some(epoch) = pre_epoch {
            self.log_commit(epoch, &commit_bytes);
        }
        let commit_envelope = ControlEnvelope::Commit {
            group_id: self.group_id.clone(),
            from_fingerprint: own_fp,
            commit_b64: encode(&commit_bytes),
            roster_version: self.own_roster_version(),
        };
        self.publish_control(&commit_envelope)
    }
    fn accept_resync_request(
        &mut self,
        from_fingerprint: String,
        have_epoch: u64,
        sender: Option<&str>,
    ) -> Result<(), PrivateGroupError> {
        if !self.acting_admin() {
            return Ok(());
        }
        // Org groups: never serve the commit log to a revoked or
        // unknown peer — the envelope names the requester (spec §6).
        if self.org_pubkey.is_some() {
            let member = sender.is_some_and(|sender| self.roster_contains(sender));
            if !member {
                return Ok(());
            }
        }
        self.serve_resync_request(from_fingerprint, have_epoch)
    }
    fn accept_resync_response(
        &mut self,
        commits: Vec<ResyncCommit>,
        sender: Option<&str>,
    ) -> Result<(), PrivateGroupError> {
        // Org groups: only a roster admin may feed us commits.
        if self.org_pubkey.is_some() && !self.commit_author_authorized("", sender) {
            return Ok(());
        }
        self.absorb_resync_response(commits)
    }
}
