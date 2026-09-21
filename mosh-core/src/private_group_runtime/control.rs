//! The control channel handlers.

use super::*;

impl GroupSession {
    pub(super) fn handle_control(
        &mut self,
        payload: Vec<u8>,
        sender_peer_id: Option<String>,
    ) -> Result<(), PrivateGroupError> {
        let envelope: ControlEnvelope = decode_json(&payload)?;
        let own_fp = self.crypto.fingerprint();
        match envelope {
            ControlEnvelope::KeyPackage {
                group_id,
                participant_id,
                key_package_b64,
                ..
            } if self.group_id == group_id && self.participant_id != participant_id => {
                if !self.acting_admin() {
                    return Ok(());
                }
                let key_package = decode(&key_package_b64)?;
                // Drop replays / rogue duplicate admit attempts whose MLS
                // signer is already covered by the roster.
                if self.crypto.key_package_signer_is_member(&key_package)? {
                    return Ok(());
                }
                if self.org_pubkey.is_some() {
                    return self.admit_org_member(
                        sender_peer_id.as_deref(),
                        participant_id,
                        &key_package,
                        own_fp,
                    );
                }
                let pre_epoch = self.crypto.epoch();
                let outcome = self.crypto.add_members(&[key_package.as_slice()])?;
                self.broadcast_admission(pre_epoch, &outcome, participant_id, own_fp)
            }
            ControlEnvelope::Welcome {
                group_id,
                for_participant_id,
                from_fingerprint,
                welcome_b64,
                tree_b64,
                commit_b64,
            } if !self.joined
                && !self.is_admin
                && self.group_id == group_id
                && self.participant_id == for_participant_id =>
            {
                if !self.commit_author_authorized(&from_fingerprint, sender_peer_id.as_deref()) {
                    return Ok(());
                }
                self.crypto
                    .join_welcome(&decode(&welcome_b64)?, &decode(&tree_b64)?)?;
                self.joined = true;
                // The Welcome already carries the admission commit's state. The
                // admin also broadcasts that same commit on the control channel
                // for existing members, so mark it processed to skip re-applying
                // it to ourselves (which would error on the already-merged epoch).
                self.sequencer.mark_seen(commit_b64);
                Ok(())
            }
            ControlEnvelope::Welcome {
                group_id,
                from_fingerprint,
                commit_b64,
                ..
            } if self.joined && !self.is_admin && self.group_id == group_id => {
                if !self.commit_author_authorized(&from_fingerprint, sender_peer_id.as_deref()) {
                    return Ok(());
                }
                self.apply_commit_sequenced(commit_b64)
            }
            ControlEnvelope::Commit {
                group_id,
                from_fingerprint,
                commit_b64,
                roster_version,
            } if self.joined && self.group_id == group_id => {
                if self.org_pubkey.is_some() {
                    // Roster-derived authority incl. the lag buffer; own
                    // commits come back around but dedup as already-applied.
                    self.apply_org_commit(commit_b64, roster_version, sender_peer_id.as_deref())
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
            ControlEnvelope::SelfRemove {
                group_id,
                from_fingerprint,
                proposal_b64,
            } if self.group_id == group_id && from_fingerprint != own_fp => {
                if !self.should_commit_departure(&from_fingerprint) {
                    return Ok(());
                }
                let proposal = decode(&proposal_b64)?;
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
            ControlEnvelope::ResyncRequest {
                group_id,
                from_fingerprint,
                have_epoch,
            } if self.group_id == group_id && from_fingerprint != own_fp => {
                if !self.acting_admin() {
                    return Ok(());
                }
                // Org groups: never serve the commit log to a revoked or
                // unknown peer — the envelope names the requester (spec §6).
                if self.org_pubkey.is_some() {
                    let member = sender_peer_id
                        .as_deref()
                        .map(str::to_string)
                        .is_some_and(|sender| self.roster_contains(&sender));
                    if !member {
                        return Ok(());
                    }
                }
                self.serve_resync_request(from_fingerprint, have_epoch)
            }
            ControlEnvelope::ResyncResponse {
                group_id,
                for_fingerprint,
                commits,
            } if self.joined && self.group_id == group_id && for_fingerprint == own_fp => {
                // Org groups: only a roster admin may feed us commits.
                if self.org_pubkey.is_some()
                    && !self.commit_author_authorized("", sender_peer_id.as_deref())
                {
                    return Ok(());
                }
                self.absorb_resync_response(commits)
            }
            ControlEnvelope::AttachmentManifest {
                group_id,
                participant_id,
                from_device,
                from_fingerprint,
                manifest_ciphertext_b64,
            } if self.joined
                && self.group_id == group_id
                && participant_id != self.participant_id =>
            {
                let manifest_json = self.crypto.decrypt(&decode(&manifest_ciphertext_b64)?)?;
                let manifest: AttachmentManifest = decode_json(&manifest_json)?;
                self.accept_incoming_manifest(from_device, from_fingerprint, manifest)
            }
            ControlEnvelope::DmOffer { group_id, offer } if self.group_id == group_id => {
                self.dm_offers.receive(offer, &self.device_fingerprint);
                Ok(())
            }
            ControlEnvelope::TypingIndicator {
                group_id,
                from_device,
                from_fingerprint,
                typing_ciphertext_b64,
            } if self.joined && self.group_id == group_id && from_fingerprint != own_fp => {
                // Decrypting authenticates: only a group member can produce a
                // ciphertext this MLS group accepts, so a forged hint stops
                // here. A wrong fingerprint claim is likewise dropped — the
                // claim is self-asserted, but an inconsistent one is not worth
                // a hint.
                let Ok(ciphertext) = decode(&typing_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::VERIFY,
                        &group_id,
                        "dropping unverifiable typing hint",
                    );
                    return Ok(());
                };
                if let Ok(body) = decode_json::<GroupTypingBody>(&plaintext) {
                    if body.device != from_device {
                        return Ok(());
                    }
                }
                self.note_member_typing(from_fingerprint, &from_device, now_ms());
                Ok(())
            }
            _ => Ok(()),
        }
    }
}
