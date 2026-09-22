//! Group lifecycle: rehydrate, create, join.

use super::*;

impl PrivateGroupRuntime {
    /// Rebuild private groups + history from the encrypted store. Best-effort:
    /// a corrupt group row is skipped so one bad record does not block startup.
    pub fn rehydrate(&mut self) {
        let Some(p) = self.groups.persistence().cloned() else {
            return;
        };
        for rec in self.groups.stored_records::<PersistedGroupSession>() {
            let snapshot = match p.get_group_mls_snapshot(&rec.group_id) {
                Ok(Some(snapshot)) => snapshot,
                Ok(None) => {
                    // A record without its MLS group can never rebuild: a
                    // joiner placeholder (not joined, empty MLS group id) is
                    // dead data and gets deleted; anything else is corruption
                    // whose history rows stay recoverable, so the row is kept.
                    if rec.mls_group_id.is_empty() && !rec.joined {
                        let message = match p.delete_group(&rec.group_id) {
                            Ok(()) => "dropping joiner record without MLS snapshot".to_string(),
                            Err(e) => {
                                format!("joiner record without MLS snapshot; delete failed: {e}")
                            }
                        };
                        dlog::write(LogLevel::Info, kinds::REHYDRATE, &rec.group_id, &message);
                    } else {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::REHYDRATE,
                            &rec.group_id,
                            "record without MLS snapshot; row kept",
                        );
                    }
                    continue;
                }
                Err(e) => {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::REHYDRATE,
                        &rec.group_id,
                        &format!("MLS snapshot unreadable: {e}"),
                    );
                    continue;
                }
            };
            let crypto = match MlsSessionCrypto::restore(
                &rec.display_name,
                &rec.signer_public,
                &snapshot,
                &rec.mls_group_id,
            ) {
                Ok(crypto) => crypto,
                Err(error) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::REHYDRATE,
                        &rec.group_id,
                        &format!("crypto restore failed: {error}"),
                    );
                    continue;
                }
            };
            let node = match self.open_group_room(
                &rec.mesh_id,
                &rec.group_id,
                rec.listen_port,
                rec.static_peer.clone(),
            ) {
                Ok(node) => node,
                Err(error) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::REHYDRATE,
                        &rec.group_id,
                        &format!("node start failed: {error}"),
                    );
                    continue;
                }
            };
            let mut session = GroupSession {
                group_id: rec.group_id.clone(),
                mesh_id: rec.mesh_id.clone(),
                label: rec.label.clone(),
                display_name: rec.display_name.clone(),
                participant_id: rec.participant_id.clone(),
                device_fingerprint: node
                    .public_key_hex()
                    .unwrap_or_else(|| rec.device_fingerprint.clone()),
                creator_fingerprint: rec.creator_fingerprint.clone(),
                current_admin_fingerprint: rec.current_admin_fingerprint.clone(),
                is_admin: rec.is_admin,
                invite_uri: rec.invite_uri.clone(),
                joined: rec.joined,
                listen_port: rec.listen_port,
                static_peer: rec.static_peer.clone(),
                node,
                crypto,
                messages: MessageLog::default(),
                seen: SeenFrames::default(),
                sequencer: CommitSequencer::new(),
                persistence: Some(Arc::clone(&p)),
                needs_rejoin: false,
                control_channel: format!("{CONTROL_CHANNEL_PREFIX}{}", rec.group_id),
                data_channel: format!("{DATA_CHANNEL_PREFIX}{}", rec.group_id),
                blob_channel: format!("{BLOB_CHANNEL_PREFIX}{}", rec.group_id),
                transfer: Transfer::new(Arc::clone(self.groups.attachment_store())),
                outbound_attempts: HashMap::new(),
                dm_offers: DmOffers::default(),
                org_pubkey: rec.org_pubkey.clone(),
                // Identity was mandatory at create/join time; if the blob
                // vanished, the org group cannot sign control traffic — skip
                // it rather than degrade to unauthenticated frames.
                org_signer: match rec.org_pubkey.as_deref() {
                    Some(_) => match load_org_signer(Some(p.as_ref())) {
                        Ok(signer) => Some(signer),
                        Err(error) => {
                            dlog::write(
                                LogLevel::Error,
                                kinds::REHYDRATE,
                                &rec.group_id,
                                &format!("org signer unavailable: {error}"),
                            );
                            continue;
                        }
                    },
                    None => None,
                },
                roster_cache: None,
                roster_lag: Vec::new(),
                last_roster_version_seen: None,
                typing_members: HashMap::new(),
                member_names: HashMap::new(),
                typing_gate: TypingGate::default(),
            };
            // The persisted MLS tree outranks the persisted admin pointer: if
            // the admin left while we were down, the restored tree already
            // says so.
            session.reconcile_admin();
            // A member may have missed commits while offline; ask the admin
            // for a replay. Best-effort: the mesh may not be connected yet —
            // a real gap re-triggers on the next out-of-order commit. Skip
            // when epoch is None (not joined into MLS): the admin would replay
            // its whole log while every entry no-ops.
            if session.joined && !session.is_admin {
                if let Some(have_epoch) = session.crypto.epoch() {
                    let request = ControlEnvelope::ResyncRequest {
                        group_id: session.group_id.clone(),
                        from_fingerprint: session.crypto.fingerprint(),
                        have_epoch,
                    };
                    let _ = session.publish_control(&request);
                }
            }
            self.groups.replay(
                &rec.group_id,
                Restore {
                    log: &mut session.messages,
                    attempts: &mut session.outbound_attempts,
                    transfer: &mut session.transfer,
                    local_author: &rec.device_fingerprint,
                },
            );
            // The record just read off disk already carries a valid MLS
            // group id, so the tail write must not replace it with itself.
            self.groups.mark_record_final(&rec.group_id);
            self.groups.insert(rec.group_id, session);
        }
    }

    pub fn create_group(
        &mut self,
        request: CreateGroupRequest,
    ) -> Result<GroupCreated, PrivateGroupError> {
        let label = sanitize_label(request.label)?;
        let listen_port = request.listen_port;
        let static_peer = request.static_peer.clone();
        let org_signer = match request.org_pubkey.as_deref() {
            Some(_) => Some(load_org_signer(self.groups.persistence().map(Arc::as_ref))?),
            None => None,
        };
        // Org groups bind the MLS leaf to the durable moss peer-id
        // (ADR 0004); plain groups keep the display-name credential.
        let credential_identity = org_signer
            .as_ref()
            .map(org_signing::peer_id_hex)
            .unwrap_or_else(|| request.display_name.clone());
        let mut crypto = MlsSessionCrypto::new(&credential_identity)?;
        crypto.create_group()?;
        let group_id = crypto.random_token("group")?;
        let mesh_id = crypto.random_token("groupmesh")?;
        let participant_id = crypto.random_token("participant")?;
        let creator_fingerprint = crypto.fingerprint();
        let node = self.open_group_room(&mesh_id, &group_id, listen_port, static_peer.clone())?;
        // The room is open on the shared node: bailing without closing it
        // would pin the node up with subscriptions nothing ever clears.
        let device_fingerprint = match node.public_key_hex() {
            Some(value) => value,
            None => {
                runtime::close_room(
                    &self.shared_node,
                    &node,
                    &mesh_id,
                    &group_channels(&group_id),
                    &format!("{KIND} {group_id}"),
                );
                return Err(PrivateGroupError::Moss(
                    "public key unavailable".to_string(),
                ));
            }
        };
        let invite_uri = build_invite_uri(&mesh_id, &group_id, &creator_fingerprint, &label);

        let session = GroupSession {
            group_id: group_id.clone(),
            mesh_id: mesh_id.clone(),
            label: label.clone(),
            display_name: request.display_name,
            participant_id,
            device_fingerprint,
            creator_fingerprint: creator_fingerprint.clone(),
            current_admin_fingerprint: creator_fingerprint.clone(),
            is_admin: true,
            invite_uri: Some(invite_uri.clone()),
            joined: true,
            listen_port,
            static_peer,
            node,
            crypto,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            sequencer: CommitSequencer::new(),
            persistence: self.groups.persistence().cloned(),
            needs_rejoin: false,
            control_channel: format!("{CONTROL_CHANNEL_PREFIX}{group_id}"),
            data_channel: format!("{DATA_CHANNEL_PREFIX}{group_id}"),
            blob_channel: format!("{BLOB_CHANNEL_PREFIX}{group_id}"),
            transfer: Transfer::new(Arc::clone(self.groups.attachment_store())),
            outbound_attempts: HashMap::new(),
            dm_offers: DmOffers::default(),
            org_pubkey: request.org_pubkey,
            org_signer,
            roster_cache: None,
            roster_lag: Vec::new(),
            last_roster_version_seen: None,
            typing_members: HashMap::new(),
            member_names: HashMap::new(),
            typing_gate: TypingGate::default(),
        };

        self.groups.insert(group_id.clone(), session);
        self.groups.persist_tail();
        Ok(GroupCreated {
            group_id,
            mesh_id,
            invite_uri,
            fingerprint: creator_fingerprint,
            label,
        })
    }

    pub fn join_group(
        &mut self,
        request: JoinGroupRequest,
    ) -> Result<GroupSnapshot, PrivateGroupError> {
        let invite = ParsedGroupInvite::parse(&request.invite_uri)?;
        if self.groups.holds(&invite.group_id) {
            return Err(PrivateGroupError::DuplicateGroup(invite.group_id));
        }
        let listen_port = request.listen_port;
        let static_peer = request.static_peer.clone();
        let org_signer = match request.org_pubkey.as_deref() {
            Some(_) => Some(load_org_signer(self.groups.persistence().map(Arc::as_ref))?),
            None => None,
        };
        let credential_identity = org_signer
            .as_ref()
            .map(org_signing::peer_id_hex)
            .unwrap_or_else(|| request.display_name.clone());
        let mut crypto = MlsSessionCrypto::new(&credential_identity)?;
        let participant_id = crypto.random_token("participant")?;
        let key_package = crypto.key_package_bytes()?;
        let node = self.open_group_room(
            &invite.mesh_id,
            &invite.group_id,
            listen_port,
            static_peer.clone(),
        )?;
        // The room is open on the shared node: bailing without closing it
        // would pin the node up with subscriptions nothing ever clears.
        // Covers both the missing public key and a KeyPackage publish that
        // never left the device — in either case no session will exist to
        // close the room later.
        let joined_or_closed = (|| {
            let device_fingerprint = node
                .public_key_hex()
                .ok_or_else(|| PrivateGroupError::Moss("public key unavailable".to_string()))?;
            let envelope = ControlEnvelope::KeyPackage {
                group_id: invite.group_id.clone(),
                participant_id: participant_id.clone(),
                from_device: request.display_name.clone(),
                from_fingerprint: device_fingerprint.clone(),
                key_package_b64: encode(&key_package),
            };
            publish_control_message(
                &node,
                &format!("{CONTROL_CHANNEL_PREFIX}{}", invite.group_id),
                &invite.mesh_id,
                org_context(request.org_pubkey.as_deref(), org_signer.as_ref()),
                &envelope,
            )
            .map(|_| device_fingerprint)
        })();
        let device_fingerprint = match joined_or_closed {
            Ok(value) => value,
            Err(error) => {
                runtime::close_room(
                    &self.shared_node,
                    &node,
                    &invite.mesh_id,
                    &group_channels(&invite.group_id),
                    &format!("{KIND} {}", invite.group_id),
                );
                return Err(error);
            }
        };
        let control_channel = format!("{CONTROL_CHANNEL_PREFIX}{}", invite.group_id);
        let session = GroupSession {
            group_id: invite.group_id.clone(),
            mesh_id: invite.mesh_id,
            label: invite.label.clone(),
            display_name: request.display_name,
            participant_id,
            device_fingerprint,
            creator_fingerprint: invite.creator_fingerprint.clone(),
            current_admin_fingerprint: invite.creator_fingerprint,
            is_admin: false,
            invite_uri: Some(request.invite_uri),
            joined: false,
            listen_port,
            static_peer,
            node,
            crypto,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            sequencer: CommitSequencer::new(),
            persistence: self.groups.persistence().cloned(),
            needs_rejoin: false,
            control_channel,
            data_channel: format!("{DATA_CHANNEL_PREFIX}{}", invite.group_id),
            blob_channel: format!("{BLOB_CHANNEL_PREFIX}{}", invite.group_id),
            transfer: Transfer::new(Arc::clone(self.groups.attachment_store())),
            outbound_attempts: HashMap::new(),
            dm_offers: DmOffers::default(),
            org_pubkey: request.org_pubkey,
            org_signer,
            roster_cache: None,
            roster_lag: Vec::new(),
            last_roster_version_seen: None,
            typing_members: HashMap::new(),
            member_names: HashMap::new(),
            typing_gate: TypingGate::default(),
        };
        self.groups.insert(invite.group_id.clone(), session);
        self.poll(&invite.group_id)
    }
}
