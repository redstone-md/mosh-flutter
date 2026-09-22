//! Roster-derived authority: admin, admission, revocation.

use super::*;

impl GroupSession {
    /// Inbound control frame → (inner payload, verified sender peer-id).
    /// Org groups accept only valid `OrgSigned` frames; plain groups pass
    /// the payload through with no sender claim.
    pub(super) fn unwrap_control(
        &self,
        payload: Vec<u8>,
    ) -> Result<(Vec<u8>, Option<String>), PrivateGroupError> {
        let Some(org_pubkey) = self.org_pubkey.as_deref() else {
            return Ok((payload, None));
        };
        let env: OrgSigned = decode_json(&payload)?;
        let ctx = OrgContext {
            org_pubkey,
            mesh_id: &self.mesh_id,
            channel_kind: &self.control_channel,
        };
        org_envelope::verify(&env, &ctx)
            .map_err(|e| PrivateGroupError::Codec(format!("org envelope rejected: {e}")))?;
        Ok((env.payload, Some(env.peer_id)))
    }

    /// Latest verified roster for this group's org, re-verified only when
    /// the stored bytes change.
    pub(super) fn org_roster(&mut self) -> Option<Roster> {
        let org_pubkey = self.org_pubkey.as_deref()?;
        let bytes = self
            .persistence
            .as_ref()?
            .get_org_roster(org_pubkey)
            .ok()??;
        if let Some((cached_bytes, roster)) = self.roster_cache.as_ref() {
            if *cached_bytes == bytes {
                return Some(roster.clone());
            }
        }
        let roster = org_roster::verify(&bytes, org_pubkey, None).ok()?;
        self.roster_cache = Some((bytes, roster.clone()));
        Some(roster)
    }

    pub(super) fn roster_contains(&mut self, peer_id: &str) -> bool {
        self.org_roster()
            .is_some_and(|r| r.members.iter().any(|m| m.moss_peer_id == peer_id))
    }

    pub(super) fn roster_role_is_admin(&mut self, peer_id: &str) -> bool {
        self.org_roster().is_some_and(|r| {
            r.members
                .iter()
                .any(|m| m.moss_peer_id == peer_id && m.role == "admin")
        })
    }

    pub(super) fn own_roster_version(&mut self) -> Option<u64> {
        self.org_roster().map(|r| r.version)
    }

    pub(super) fn own_peer_id(&self) -> Option<String> {
        self.org_signer.as_ref().map(org_signing::peer_id_hex)
    }

    /// May this client author membership commits? Org groups: roster role
    /// (ADR 0005) — the fingerprint-admin machinery is not consulted at
    /// all. Plain groups: the legacy single-admin flag.
    pub(super) fn acting_admin(&mut self) -> bool {
        if self.org_pubkey.is_some() {
            return match self.own_peer_id() {
                Some(id) => self.roster_role_is_admin(&id),
                None => false,
            };
        }
        self.is_admin
    }

    /// Re-derive the admin from the MLS tree. While the admin still holds a
    /// leaf nothing changes; once it is gone the successor takes over. Every
    /// member runs this over the same tree, so the admin follows the commit
    /// that drops the leaf — no frame has to survive for the group to agree.
    /// Plain groups only: org groups take authority from the signed roster
    /// (ADR 0005) and never consult a fingerprint.
    pub(super) fn reconcile_admin(&mut self) {
        if self.org_pubkey.is_some() || !self.joined {
            return;
        }
        let members = self.crypto.member_fingerprints();
        if members.contains(&self.current_admin_fingerprint) {
            return;
        }
        let Some(next) = successor_of(members, &self.current_admin_fingerprint) else {
            return;
        };
        self.is_admin = next == self.crypto.fingerprint();
        self.current_admin_fingerprint = next;
    }

    /// Are we the member expected to commit `leaver`'s self-removal? Org
    /// groups: any roster admin (ADR 0005). Plain groups: the admin — unless
    /// the admin is the one leaving, in which case the successor commits, so
    /// exactly one member acts and the resulting tree names that same member.
    pub(super) fn should_commit_departure(&mut self, leaver: &str) -> bool {
        if self.org_pubkey.is_some() {
            return self.acting_admin();
        }
        if leaver != self.current_admin_fingerprint {
            return self.is_admin;
        }
        successor_of(self.crypto.member_fingerprints(), leaver)
            .is_some_and(|next| next == self.crypto.fingerprint())
    }

    /// Is this inbound commit/welcome author allowed to move the group?
    /// Org groups: verified envelope sender has `role: admin`. Plain
    /// groups: fingerprint matches the current admin.
    pub(super) fn commit_author_authorized(
        &mut self,
        from_fingerprint: &str,
        sender_peer_id: Option<&str>,
    ) -> bool {
        if self.org_pubkey.is_some() {
            return match sender_peer_id {
                Some(sender) => {
                    let sender = sender.to_string();
                    self.roster_role_is_admin(&sender)
                }
                None => false,
            };
        }
        from_fingerprint == self.current_admin_fingerprint
    }

    /// Org commit admission with the ADR 0005 roster-lag rule: a commit
    /// from a not-yet-admin claiming a NEWER roster version is buffered and
    /// retried when that roster lands; anything else from a non-admin drops.
    pub(super) fn apply_org_commit(
        &mut self,
        commit_b64: String,
        author_roster_version: Option<u64>,
        sender_peer_id: Option<&str>,
    ) -> Result<(), PrivateGroupError> {
        let Some(sender) = sender_peer_id.map(str::to_string) else {
            return Ok(());
        };
        if self.roster_role_is_admin(&sender) {
            return self.apply_commit_sequenced(commit_b64);
        }
        if author_roster_version > self.own_roster_version() {
            // Reject absurd claims outright: an entry pinned at an
            // unreachable version (e.g. u64::MAX) would otherwise squat in
            // the buffer forever. Genuine lag is 1-2 versions deep. Checked:
            // when even `own + HORIZON` overflows, no claim can be within the
            // horizon, so everything from a non-admin drops — a plain `+`
            // would panic in debug and wrap the horizon backwards in
            // release, admitting the very claims this exists to reject.
            let claimed = author_roster_version.unwrap_or(0);
            let within_horizon = self
                .own_roster_version()
                .unwrap_or(0)
                .checked_add(ROSTER_LAG_HORIZON)
                .is_some_and(|horizon| claimed <= horizon);
            if !within_horizon {
                dlog::write(
                    LogLevel::Warn,
                    kinds::COMMIT,
                    &self.group_id,
                    &format!("commit claiming roster v{claimed} beyond horizon dropped"),
                );
                return Ok(());
            }
            // FIFO at cap: garbage must not lock out a later genuine entry.
            if self.roster_lag.len() >= ROSTER_LAG_CAP {
                self.roster_lag.remove(0);
            }
            self.roster_lag.push(RosterLaggedCommit {
                roster_version: claimed,
                sender_peer_id: sender,
                commit_b64,
            });
            return Ok(());
        }
        dlog::write(
            LogLevel::Warn,
            kinds::COMMIT,
            &self.group_id,
            &format!("commit from non-admin {sender} dropped"),
        );
        Ok(())
    }

    /// Re-run lag-buffered commits after a roster change. Entries whose
    /// author became admin apply; entries still ahead of our roster stay;
    /// entries whose claimed version we now have (author still not admin)
    /// drop for good.
    pub(super) fn retry_roster_lagged(&mut self) {
        if self.roster_lag.is_empty() {
            return;
        }
        let mine = self.own_roster_version();
        let pending = std::mem::take(&mut self.roster_lag);
        for entry in pending {
            if self.roster_role_is_admin(&entry.sender_peer_id) {
                if let Err(error) = self.apply_commit_sequenced(entry.commit_b64) {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::COMMIT,
                        &self.group_id,
                        &format!("lagged commit apply failed: {error}"),
                    );
                }
            } else if Some(entry.roster_version) > mine {
                self.roster_lag.push(entry);
            }
        }
    }

    /// One pass per roster version change, driven by the drain loop (poll
    /// cadence) and by rehydrate (`last_roster_version_seen` starts None).
    /// Retries lag-buffered commits, then reconciles group membership.
    pub(super) fn sync_roster_state(&mut self) {
        if self.org_pubkey.is_none() {
            return;
        }
        let current = self.own_roster_version();
        if current != self.last_roster_version_seen {
            self.last_roster_version_seen = current;
            self.retry_roster_lagged();
            self.reconcile_roster_membership();
        }
    }

    /// Crypto layer of revocation (spec §6, ADR 0008), reconciliation-style:
    /// any leaf whose peer-id is absent from the current verified roster is
    /// removed. Driven by durable state (persisted roster ∧ MLS tree), so a
    /// removal converges no matter which drain absorbed the roster and
    /// survives a restart — never by an in-memory removal event.
    pub(super) fn reconcile_roster_membership(&mut self) {
        let Some(roster) = self.org_roster() else {
            return;
        };
        if !self.joined || !self.acting_admin() {
            return;
        }
        let own = self.own_peer_id();
        let revoked: Vec<String> = self
            .crypto
            .member_identities()
            .into_iter()
            .filter(|identity| Some(identity) != own.as_ref())
            .filter(|identity| !roster.members.iter().any(|m| m.moss_peer_id == *identity))
            .collect();
        for peer_id in revoked {
            let own_fp = self.crypto.fingerprint();
            let pre_epoch = self.crypto.epoch();
            let commit_bytes = match self.crypto.remove_members_by_identity(&peer_id) {
                Ok(bytes) => bytes,
                Err(error) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::KICK,
                        &self.group_id,
                        &format!("auto-kick of {peer_id} failed: {error}"),
                    );
                    continue;
                }
            };
            if let Some(epoch) = pre_epoch {
                self.log_commit(epoch, &commit_bytes);
            }
            let commit_envelope = ControlEnvelope::Commit {
                group_id: self.group_id.clone(),
                from_fingerprint: own_fp,
                commit_b64: encode(&commit_bytes),
                roster_version: Some(roster.version),
            };
            if let Err(error) = self.publish_control(&commit_envelope) {
                dlog::write(
                    LogLevel::Error,
                    kinds::KICK,
                    &self.group_id,
                    &format!("auto-kick commit publish failed: {error}"),
                );
            }
        }
    }

    /// Org admission rule (ADR 0004): the KeyPackage's credential identity
    /// must equal the envelope's verified peer-id AND be in the roster.
    /// `replace_member` removes any stale leaf with the same identity in the
    /// same commit (rejoin/device-replace dedup); with none it's a plain Add.
    pub(super) fn admit_org_member(
        &mut self,
        sender_peer_id: Option<&str>,
        participant_id: String,
        key_package: &[u8],
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        let Some(sender) = sender_peer_id else {
            return Ok(());
        };
        let identity = self.crypto.key_package_identity(key_package)?;
        if identity != sender {
            dlog::write(
                LogLevel::Warn,
                kinds::VERIFY,
                &self.group_id,
                &format!("key package identity does not match envelope sender {sender}; dropped"),
            );
            return Ok(());
        }
        if !self.roster_contains(&identity) {
            dlog::write(
                LogLevel::Warn,
                kinds::VERIFY,
                &self.group_id,
                &format!("joiner {identity} not in org roster; dropped"),
            );
            return Ok(());
        }
        let pre_epoch = self.crypto.epoch();
        let outcome = self.crypto.replace_member(&identity, key_package)?;
        self.broadcast_admission(pre_epoch, &outcome, participant_id, own_fp)
    }

    pub(super) fn broadcast_admission(
        &mut self,
        pre_epoch: Option<u64>,
        outcome: &AddOutcome,
        participant_id: String,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        if let Some(epoch) = pre_epoch {
            self.log_commit(epoch, &outcome.commit_bytes);
        }
        let commit_b64 = encode(&outcome.commit_bytes);
        let welcome_envelope = ControlEnvelope::Welcome {
            group_id: self.group_id.clone(),
            for_participant_id: participant_id,
            from_fingerprint: own_fp.clone(),
            welcome_b64: encode(&outcome.welcome_bytes),
            commit_b64: commit_b64.clone(),
            tree_b64: encode(&outcome.tree_bytes),
        };
        self.publish_control(&welcome_envelope)?;
        // Existing members need the Commit on the control channel so their
        // MLS tree advances; the Welcome above is consumed only by the joiner.
        let commit_envelope = ControlEnvelope::Commit {
            group_id: self.group_id.clone(),
            from_fingerprint: own_fp,
            commit_b64,
            roster_version: self.own_roster_version(),
        };
        self.publish_control(&commit_envelope)
    }
}
