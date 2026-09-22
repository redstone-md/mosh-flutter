//! MLS commits, sequencing, and resync.

use super::*;

impl GroupSession {
    pub(super) fn handle_moss_message(
        &mut self,
        message: MossReceivedMessage,
    ) -> Result<(), PrivateGroupError> {
        // Control frames are exempt from the replay set, the same rule the
        // DM runtime pins for its own control channel: every branch of
        // `handle_control` is idempotent (the sequencer dedups applied
        // commits, a KeyPackage dedups by signer-is-member, a Welcome is
        // `!joined`-guarded, manifests and offers dedup by id), and
        // re-delivery is the recovery mechanism. Recording a control frame
        // BEFORE processing it would blackhole the bytes of anything that
        // failed — a retransmission could never repair the session because
        // the hash of the failed frame was already filed as seen.
        if message.channel != self.control_channel
            && self.seen.seen_before(&message.channel, &message.payload)
        {
            return Ok(());
        }
        if message.channel == self.control_channel {
            let (payload, sender_peer_id) = self.unwrap_control(message.payload)?;
            let result = self.handle_control(payload, sender_peer_id);
            // Control frames are the only ones that move the MLS tree, by any
            // route: a commit, a resync replay, a Welcome, or a departure we
            // committed ourselves. Derive the admin once, here, rather than at
            // each of them — and on the error path too, since a frame that
            // failed late may still have changed membership.
            self.reconcile_admin();
            result
        } else if message.channel == self.data_channel {
            self.handle_data(message.payload)
        } else if message.channel == self.blob_channel {
            self.handle_blob(message.payload)
        } else {
            Ok(())
        }
    }

    /// Merge a control-channel commit in epoch order. Duplicates and stale
    /// replays are no-ops; future commits are buffered and drained once their
    /// epoch is reached; an unreachable buffered commit triggers a resync
    /// request (spec §7).
    pub(super) fn apply_commit_sequenced(
        &mut self,
        commit_b64: String,
    ) -> Result<(), PrivateGroupError> {
        let outcome = sequence_commit(
            &mut self.crypto,
            &mut self.sequencer,
            self.persistence.as_deref(),
            &self.group_id,
            &commit_b64,
        )?;
        match outcome {
            SequenceOutcome::Done => {
                // A real commit closed the gap: clear any stale rejoin hint so
                // a transient/forged gap can never wedge the flag permanently.
                self.needs_rejoin = false;
                Ok(())
            }
            SequenceOutcome::Gapped => self.request_resync_if_gapped(),
        }
    }

    pub(super) fn request_resync_if_gapped(&mut self) -> Result<(), PrivateGroupError> {
        let Some(current) = self.crypto.epoch() else {
            return Ok(());
        };
        if !self.sequencer.gap(current) || !self.sequencer.should_request(current) {
            return Ok(());
        }
        let request = ControlEnvelope::ResyncRequest {
            group_id: self.group_id.clone(),
            from_fingerprint: self.crypto.fingerprint(),
            have_epoch: current,
        };
        // Undo the request reservation if publishing failed, so the next gap
        // sighting retries instead of going silent until restart.
        let result = self.publish_control(&request);
        if result.is_err() {
            self.sequencer.rearm();
        }
        result
    }

    /// Admin-only: reply to a member's ResyncRequest with logged commits >=
    /// have_epoch. A DB read error skips the reply rather than sending an
    /// empty one (which the requester would read as "unbridgeable → rejoin").
    pub(super) fn serve_resync_request(
        &self,
        for_fingerprint: String,
        have_epoch: u64,
    ) -> Result<(), PrivateGroupError> {
        let Some(p) = self.persistence.as_ref() else {
            return Ok(());
        };
        let rows = match p.list_group_commits_from(&self.group_id, have_epoch) {
            Ok(rows) => rows,
            Err(e) => {
                dlog::write(
                    LogLevel::Warn,
                    kinds::RESYNC,
                    &self.group_id,
                    &format!("resync read failed: {e}"),
                );
                return Ok(());
            }
        };
        let commits = rows
            .into_iter()
            .map(|(epoch, bytes)| ResyncCommit {
                epoch,
                commit_b64: encode(&bytes),
            })
            .collect();
        let response = ControlEnvelope::ResyncResponse {
            group_id: self.group_id.clone(),
            for_fingerprint,
            commits,
        };
        self.publish_control(&response)
    }

    /// Requester side: feed an admin's replay through sequencing. If a gap
    /// remains, try one more request from the advanced epoch before declaring
    /// rejoin; otherwise clear any stale rejoin hint.
    pub(super) fn absorb_resync_response(
        &mut self,
        commits: Vec<ResyncCommit>,
    ) -> Result<(), PrivateGroupError> {
        let still_gapped = absorb_resync_commits(
            &mut self.crypto,
            &mut self.sequencer,
            self.persistence.as_deref(),
            &self.group_id,
            commits,
        );
        if !still_gapped {
            self.needs_rejoin = false;
            return Ok(());
        }
        self.sequencer.rearm();
        self.request_resync_if_gapped()?;
        if self
            .crypto
            .epoch()
            .is_some_and(|current| self.sequencer.gap(current))
        {
            self.needs_rejoin = true;
        }
        Ok(())
    }

    pub(super) fn log_commit(&self, epoch: u64, commit_bytes: &[u8]) {
        log_group_commit(
            self.persistence.as_deref(),
            &self.group_id,
            epoch,
            commit_bytes,
        );
    }
}
