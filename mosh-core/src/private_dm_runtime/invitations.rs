//! Durable invitation ownership, chat visibility and replacement.
use super::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct InviteLifecycle {
    pub opened: bool,
    pub consumed: bool,
    pub admitted_signer: Option<String>,
    pub welcome_payload: Option<Vec<u8>>,
    pub peer_name: Option<String>,
}

impl InviteLifecycle {
    pub(super) fn new(opened: bool) -> Self {
        Self {
            opened,
            consumed: false,
            admitted_signer: None,
            welcome_payload: None,
            peer_name: None,
        }
    }
}

impl PrivateDmSession {
    pub(super) fn is_visible(&self) -> bool {
        self.invitation
            .as_ref()
            .is_none_or(|invite| invite.opened || invite.consumed)
    }

    pub(super) fn invite_available(&self) -> bool {
        matches!(self.role, SessionRole::Alice)
            && !self.peer_joined
            && self.invite_uri.is_some()
            && !self
                .invitation
                .as_ref()
                .is_some_and(|invite| invite.consumed)
    }

    pub(super) fn created_invite(&self) -> Result<InviteCreated, PrivateDmRuntimeError> {
        Ok(InviteCreated {
            invite_uri: self
                .invite_uri
                .clone()
                .ok_or(PrivateDmRuntimeError::NotReady)?,
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            fingerprint: self.fingerprint.clone(),
            listen_address: listen_address(),
        })
    }

    pub(super) fn close_invitation_room(&self) {
        self.transport.close_room(
            &self.mesh_id,
            &session_channels(&self.session_id),
            &format!("{KIND} {}", self.session_id),
        );
    }

    /// The capability is checked before either legacy or signed admission.
    /// A missing token remains valid only for an invitation never rotated.
    pub(super) fn verify_admission_token(
        &self,
        supplied: Option<&str>,
    ) -> Result<(), PrivateDmRuntimeError> {
        let expected = self
            .invite_uri
            .as_deref()
            .map(invite_ownership::invitation_token)
            .transpose()
            .map_err(PrivateDmRuntimeError::InvalidInvite)?
            .flatten();
        if expected.as_deref() != supplied {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "invitation has been replaced".into(),
            ));
        }
        Ok(())
    }

    pub(super) fn invitation_uri(&self, token: &str) -> Result<String, PrivateDmRuntimeError> {
        let mut uri = url::Url::parse(&build_invite_uri(
            &self.mesh_id,
            &self.session_id,
            &self.fingerprint,
            self.transport.local_peer_id().as_deref(),
        ))
        .map_err(|error| PrivateDmRuntimeError::InvalidInvite(error.to_string()))?;
        uri.query_pairs_mut().append_pair("token", token);
        if let Some(target) = self.expected_invitee()? {
            uri.query_pairs_mut().append_pair("target", &target);
        }
        self.transport
            .authenticate_invite(uri.as_str(), &self.crypto)
            .map_err(PrivateDmRuntimeError::InvalidInvite)
    }
}

impl PrivateDmRuntime {
    pub fn create_pending_invite(
        &mut self,
        request: StartSessionRequest,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        self.create_invitation(request, false)
    }

    pub fn list_pending_invites(&mut self) -> Result<Vec<InviteCreated>, PrivateDmRuntimeError> {
        self.drain_inbound();
        let mut invites: Vec<_> = self
            .sessions
            .values()
            .filter(|session| !session.is_visible() && session.invite_available())
            .map(PrivateDmSession::created_invite)
            .collect::<Result<_, _>>()?;
        invites.sort_by(|a, b| a.session_id.cmp(&b.session_id));
        Ok(invites)
    }

    pub fn open_session(
        &mut self,
        session_id: &str,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        if session.is_visible() {
            return Ok(session.snapshot());
        }
        let previous = session.invitation.clone();
        if let Some(invite) = &mut session.invitation {
            invite.opened = true;
        }
        if let Some(store) = &session.device_store {
            if let Err(error) = session.write_extra(store) {
                session.invitation = previous;
                return Err(error.into());
            }
        }
        session.record_dirty = true;
        Ok(session.snapshot())
    }

    pub fn replace_invite(
        &mut self,
        session_id: &str,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        // Resolve already-arrived admission before rotating the capability.
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        if !session.invite_available() {
            return Err(PrivateDmRuntimeError::NotReady);
        }
        let token = session.crypto.random_token("invite")?;
        let uri = session.invitation_uri(&token)?;
        let previous = session.invite_uri.replace(uri);
        if let Some(store) = &session.device_store {
            if let Err(error) = session.write_extra(store) {
                session.invite_uri = previous;
                return Err(error.into());
            }
        }
        session.record_dirty = true;
        session.created_invite()
    }
}

#[cfg(test)]
#[path = "invitation_tests.rs"]
mod tests;
