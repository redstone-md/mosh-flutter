//! Resume an org acceptance with the original MLS KeyPackage private material.

use super::*;
use crate::org_runtime::PendingJoinRecovery;

impl PrivateDmRuntime {
    pub(crate) fn join_recovery(
        &self,
        session_id: &str,
    ) -> Result<PendingJoinRecovery, PrivateDmRuntimeError> {
        let session = self.session_ref(session_id)?;
        let key_package = session
            .pending_key_package
            .as_deref()
            .map(|payload| {
                admission_authentication::admission_key_package(payload, &session.mesh_id)
            })
            .transpose()?
            .flatten();
        Ok(PendingJoinRecovery {
            provider_snapshot: session.crypto.snapshot(),
            participant_id: session.participant_id.clone(),
            mls_group_id: session.crypto.group_id_bytes().unwrap_or_default(),
            key_package,
        })
    }

    pub(crate) fn accept_invite_restoring(
        &mut self,
        request: AcceptInviteRequest,
        recovery: Option<(Vec<u8>, PendingJoinRecovery)>,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        let id = self.prepare_invite_restoring(request, recovery)?;
        if let Err(error) = self.publish_prepared_join(&id) {
            self.discard_prepared_join(&id);
            return Err(error);
        }
        self.poll_session(&id)
    }

    /// Prepare and hold the original KeyPackage without publishing or polling.
    pub(crate) fn prepare_invite_restoring(
        &mut self,
        request: AcceptInviteRequest,
        recovery: Option<(Vec<u8>, PendingJoinRecovery)>,
    ) -> Result<String, PrivateDmRuntimeError> {
        let invite = ParsedInvite::parse(&request.invite_uri)?;
        if self.sessions.holds(&invite.session_id) {
            return Err(PrivateDmRuntimeError::DuplicateSession(invite.session_id));
        }
        let prepared = PendingJoinRecovery::prepare(&request.display_name, recovery)?;
        let mut session =
            self.prepare_invitee(request, invite, prepared.crypto, prepared.participant_id)?;
        if let Err(error) = stage_admission(&mut session, prepared.key_package) {
            session.transport.close_room(
                &session.mesh_id,
                &session_channels(&session.session_id),
                &format!("{KIND} {}", session.session_id),
            );
            return Err(error);
        }
        let id = session.session_id.clone();
        self.sessions.insert(id.clone(), session);
        // Pending sessions save only MLS material; the first Welcome saves the
        // native record and its matching snapshot atomically.
        Ok(id)
    }

    pub(crate) fn publish_prepared_join(&mut self, id: &str) -> Result<(), PrivateDmRuntimeError> {
        let session = self.session_mut(id)?;
        if let Some(payload) = session.pending_key_package.clone() {
            session.route_send(ChannelKind::Control, &payload)?;
            session.last_handshake_send_ms = now_ms();
        }
        Ok(())
    }

    /// Preparation has not written native rows; release only the new local owner.
    pub(crate) fn discard_prepared_join(&mut self, id: &str) {
        if let Some(session) = self.sessions.remove(id) {
            session.transport.close_room(
                &session.mesh_id,
                &session_channels(id),
                &format!("{KIND} {id}"),
            );
        }
        self.sessions.forget(id);
    }

    fn prepare_invitee(
        &mut self,
        request: AcceptInviteRequest,
        invite: ParsedInvite,
        crypto: MlsSessionCrypto,
        participant_id: String,
    ) -> Result<PrivateDmSession, PrivateDmRuntimeError> {
        let static_peer = request.static_peer.or(invite.peer_address);
        self.open_dm_room(
            &invite.mesh_id,
            &invite.session_id,
            request.listen_port,
            static_peer.clone(),
        )?;
        if invite_ownership::target_peer(&request.invite_uri)
            .map_err(PrivateDmRuntimeError::InvalidInvite)?
            .is_some_and(|target| self.transport.local_peer_id().as_deref() != Some(&target))
        {
            self.transport
                .close_room(&invite.mesh_id, &session_channels(&invite.session_id), KIND);
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "invitation targets another installation".into(),
            ));
        }
        let mut session = PrivateDmSession::new(
            SessionRole::Bob,
            request.display_name,
            participant_id,
            invite.session_id,
            invite.mesh_id,
            invite.fingerprint,
            Some(request.invite_uri),
            request.listen_port,
            static_peer,
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        session.peer_moss_id = invite.peer_moss_id;
        Ok(session)
    }
}

fn stage_admission(
    session: &mut PrivateDmSession,
    key_package: Option<Vec<u8>>,
) -> Result<(), PrivateDmRuntimeError> {
    let Some(package) = key_package else {
        session.note_handshake_frame();
        return Ok(());
    };
    let envelope = ControlEnvelope::KeyPackage {
        session_id: session.session_id.clone(),
        participant_id: session.participant_id.clone(),
        from_device: session.device_id.clone(),
        key_package_b64: encode(&package),
        moss_peer_id: session.transport.local_peer_id(),
    };
    let bytes = serde_json::to_vec(&envelope)
        .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
    let bytes = if session.expected_invitee()?.is_some() {
        let proof_b64 = session
            .transport
            .authenticate_key_package(&bytes, &session.mesh_id, &session.crypto)
            .map_err(PrivateDmRuntimeError::InvalidInvite)?
            .ok_or_else(|| {
                PrivateDmRuntimeError::InvalidInvite(
                    "transport cannot authenticate targeted admission".into(),
                )
            })?;
        serde_json::to_vec(&ControlEnvelope::AuthenticatedKeyPackage {
            session_id: session.session_id.clone(),
            proof_b64,
        })
        .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?
    } else {
        bytes
    };
    session.pending_key_package = Some(bytes);
    Ok(())
}
