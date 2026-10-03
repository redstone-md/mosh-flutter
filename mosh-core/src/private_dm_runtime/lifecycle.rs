//! Invite admission and restoration from encrypted history.

use super::*;

impl PrivateDmRuntime {
    /// Rebuild sessions + history from the encrypted store. Best-effort: a bad
    /// row is skipped, never fatal.
    pub fn rehydrate(&mut self) {
        let Some(p) = self.sessions.persistence().cloned() else {
            return;
        };
        for rec in self
            .sessions
            .stored_records::<contracts::PersistedSession>()
        {
            let snapshot = match p.get_mls_snapshot(&rec.session_id) {
                Ok(Some(s)) => s,
                Ok(None) => {
                    // A joiner record written before its Welcome carries an
                    // empty group_id and can never rebuild — delete the dead
                    // row instead of warning about it at every startup. A
                    // final record without its snapshot is corruption: its
                    // history rows stay recoverable, so the row is kept.
                    if rec.group_id.is_empty() {
                        let message = match p.delete_session(&rec.session_id) {
                            Ok(()) => "dropping joiner record without MLS snapshot".to_string(),
                            Err(e) => {
                                format!("joiner record without MLS snapshot; delete failed: {e}")
                            }
                        };
                        dlog::write(LogLevel::Info, kinds::REHYDRATE, &rec.session_id, &message);
                    } else {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::REHYDRATE,
                            &rec.session_id,
                            "record without MLS snapshot; row kept",
                        );
                    }
                    continue;
                }
                Err(e) => {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::REHYDRATE,
                        &rec.session_id,
                        &format!("MLS snapshot unreadable: {e}"),
                    );
                    continue;
                }
            };
            let restored = if rec.group_id.is_empty()
                && rec
                    .membership
                    .as_ref()
                    .is_some_and(|membership| membership.is_joining())
            {
                MlsSessionCrypto::restore_unjoined(&rec.display_name, &rec.signer_public, &snapshot)
            } else {
                MlsSessionCrypto::restore(
                    &rec.display_name,
                    &rec.signer_public,
                    &snapshot,
                    &rec.group_id,
                )
            };
            let crypto = match restored {
                Ok(c) => c,
                Err(e) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::REHYDRATE,
                        &rec.session_id,
                        &format!("crypto restore failed: {e}"),
                    );
                    continue;
                }
            };
            if let Err(e) = self.open_dm_room(
                &rec.mesh_id,
                &rec.session_id,
                rec.listen_port,
                rec.static_peer.clone(),
            ) {
                dlog::write(
                    LogLevel::Error,
                    kinds::REHYDRATE,
                    &rec.session_id,
                    &format!("node start failed: {e}"),
                );
                continue;
            }
            let session = self.restore_session(&rec, crypto);
            // The loaded record already has a valid group_id; don't rewrite it.
            self.sessions.mark_record_final(&rec.session_id);
            self.sessions.insert(rec.session_id.clone(), session);
        }
    }

    /// One session back from its record, with the history replayed into it
    /// and the handshake state read off what came back.
    pub(super) fn restore_session(
        &mut self,
        rec: &contracts::PersistedSession,
        crypto: MlsSessionCrypto,
    ) -> PrivateDmSession {
        let role = if rec.role_is_alice {
            SessionRole::Alice
        } else {
            SessionRole::Bob
        };
        let mut session = PrivateDmSession::new(
            role,
            rec.display_name.clone(),
            rec.participant_id.clone(),
            rec.session_id.clone(),
            rec.mesh_id.clone(),
            rec.fingerprint.clone(),
            rec.invite_uri.clone(),
            rec.listen_port,
            rec.static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        // Without this the restored session cannot tell whether its
        // counterpart is reachable, and cannot ask the transport to reach it.
        session.peer_moss_id = rec.peer_moss_id.clone();
        session.membership = rec.membership.clone();
        session.device_store = self.sessions.persistence().cloned();
        // Read state rides the session record: ids the counterpart had
        // authenticated a read of before the restart. Without this a restart
        // would re-ask the counterpart for every receipt it already sent.
        session.peer_read_ids = rec.read_message_ids.clone();
        self.sessions.replay(
            &rec.session_id,
            Restore {
                log: &mut session.messages,
                attempts: &mut session.outbound_attempts,
                transfer: &mut session.transfer,
                local_author: &rec.display_name,
            },
        );
        session.note_restored_history();
        session
    }

    pub fn create_invite(
        &mut self,
        request: StartSessionRequest,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        let persist_listen_port = request.listen_port;
        let persist_static_peer = request.static_peer.clone();
        let mut crypto = MlsSessionCrypto::new(&request.display_name)?;
        crypto.create_group()?;
        let session_id = crypto.random_token("session")?;
        let mesh_id = crypto.random_token("mesh")?;
        let participant_id = crypto.random_token("participant")?;
        let fingerprint = crypto.fingerprint();
        self.open_dm_room(
            &mesh_id,
            &session_id,
            request.listen_port,
            request.static_peer,
        )?;
        // Embed our moss peer id so the joiner can ask the transport to reach
        // us before organic discovery finds us.
        let invite_uri = build_invite_uri(
            &mesh_id,
            &session_id,
            &fingerprint,
            self.transport.local_peer_id().as_deref(),
        );

        let session = PrivateDmSession::new(
            SessionRole::Alice,
            request.display_name,
            participant_id,
            session_id.clone(),
            mesh_id.clone(),
            fingerprint.clone(),
            Some(invite_uri.clone()),
            persist_listen_port,
            persist_static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );

        self.sessions.insert(session_id.clone(), session);

        // Alice's group exists from create_group(), so the record is final the
        // moment it is written.
        self.sessions.persist_record(&session_id, true)?;

        Ok(InviteCreated {
            invite_uri,
            session_id,
            mesh_id,
            fingerprint,
            listen_address: listen_address(),
        })
    }

    pub fn accept_invite(
        &mut self,
        request: AcceptInviteRequest,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        let invite = ParsedInvite::parse(&request.invite_uri)?;
        if self.sessions.holds(&invite.session_id) {
            return Err(PrivateDmRuntimeError::DuplicateSession(invite.session_id));
        }
        let persist_listen_port = request.listen_port;
        let mut crypto = MlsSessionCrypto::new(&request.display_name)?;
        let participant_id = crypto.random_token("participant")?;
        let key_package = crypto.key_package_bytes()?;
        let persist_static_peer = request.static_peer.clone().or(invite.peer_address.clone());
        self.open_dm_room(
            &invite.mesh_id,
            &invite.session_id,
            request.listen_port,
            persist_static_peer.clone(),
        )?;
        let envelope = ControlEnvelope::KeyPackage {
            session_id: invite.session_id.clone(),
            participant_id: participant_id.clone(),
            from_device: request.display_name.clone(),
            key_package_b64: encode(&key_package),
            moss_peer_id: self.transport.local_peer_id(),
        };
        // Keep the serialized KeyPackage so the drain loop can re-publish it
        // until the Welcome arrives. The first publish below often lands before
        // the mesh link to Alice exists and is silently dropped.
        let key_package_payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;

        let mut session = PrivateDmSession::new(
            SessionRole::Bob,
            request.display_name,
            participant_id,
            invite.session_id.clone(),
            invite.mesh_id,
            invite.fingerprint,
            Some(request.invite_uri),
            persist_listen_port,
            persist_static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        // Pre-seed the creator's moss id from the invite so the transport can
        // be asked to reach it before any frame teaches it; a later
        // KeyPackage/Welcome exchange only confirms the same value. A wrong id
        // costs availability until the handshake corrects it, never identity:
        // the fingerprint still gates MLS.
        session.peer_moss_id = invite.peer_moss_id;
        // One-shot create-time KeyPackage; the handshake pump repeats it.
        session.route_send(ChannelKind::Control, &key_package_payload)?;
        session.pending_key_package = Some(key_package_payload);
        session.last_handshake_send_ms = now_ms();

        let session_id = session.session_id.clone();
        self.sessions.insert(session_id.clone(), session);

        // Deliberately NOT persisted here. Bob has no MLS group until the
        // Welcome, so a record written now would carry an empty group_id and
        // no snapshot — a row rehydrate can never rebuild, warning at every
        // startup. The first tick after the Welcome persists the record and
        // the snapshot together (persist_tail sees the now-final session).

        self.poll_session(&session_id)
    }
}
