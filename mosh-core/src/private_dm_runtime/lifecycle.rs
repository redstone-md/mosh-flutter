//! Invite admission and restoration from encrypted history.

use super::*;

#[cfg(test)]
#[path = "lifecycle_tests.rs"]
mod tests;

impl PrivateDmRuntime {
    pub(crate) fn session_signer_public(
        &self,
        session_id: &str,
    ) -> Result<Vec<u8>, PrivateDmRuntimeError> {
        Ok(self.session_ref(session_id)?.crypto.signer_public())
    }
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
        session.invitation = rec.invitation.clone();
        session.pending_welcome = rec
            .invitation
            .as_ref()
            .and_then(|invite| invite.welcome_payload.clone());
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
        self.create_invitation(request, true)
    }

    pub(super) fn create_invitation(
        &mut self,
        request: StartSessionRequest,
        opened: bool,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        let mut session = self.prepare_invitation_creator(request)?;
        session.invitation = Some(invitations::InviteLifecycle::new(opened));
        session.device_store = self.sessions.persistence().cloned();
        let signed = if opened {
            session
                .transport
                .authenticate_invite(
                    session.invite_uri.as_deref().unwrap_or_default(),
                    &session.crypto,
                )
                .map_err(PrivateDmRuntimeError::InvalidInvite)
        } else {
            session
                .crypto
                .random_token("invite")
                .map_err(PrivateDmRuntimeError::from)
                .and_then(|token| session.invitation_uri(&token))
        };
        let uri = match signed {
            Ok(uri) => uri,
            Err(error) => {
                session.close_invitation_room();
                return Err(error);
            }
        };
        session.invite_uri = Some(uri);
        self.persist_created_session(&session)?;
        let invitation = session.created_invite()?;
        let id = session.session_id.clone();
        self.sessions.insert(id.clone(), session);
        self.sessions.mark_record_final(&id);
        Ok(invitation)
    }

    fn prepare_invitation_creator(
        &mut self,
        request: StartSessionRequest,
    ) -> Result<PrivateDmSession, PrivateDmRuntimeError> {
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
            request.static_peer.clone(),
        )?;
        let uri = build_invite_uri(
            &mesh_id,
            &session_id,
            &fingerprint,
            self.transport.local_peer_id().as_deref(),
        );
        Ok(PrivateDmSession::new(
            SessionRole::Alice,
            request.display_name,
            participant_id,
            session_id,
            mesh_id,
            fingerprint,
            Some(uri),
            request.listen_port,
            request.static_peer,
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        ))
    }

    fn persist_created_session(
        &self,
        session: &PrivateDmSession,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(store) = self.sessions.persistence() else {
            return Ok(());
        };
        if let Err(error) = session.write_extra(store) {
            session.close_invitation_room();
            return Err(error.into());
        }
        Ok(())
    }

    pub fn accept_invite(
        &mut self,
        request: AcceptInviteRequest,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        self.accept_invite_restoring(request, None)
    }
}
