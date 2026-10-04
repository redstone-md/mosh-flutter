//! Group offers pin both endpoints before a DM accepts its first member.
use super::*;
use crate::sender_auth::SenderProof;

fn admission_context(mesh: &str) -> crate::org_envelope::OrgContext<'_> {
    crate::org_envelope::OrgContext {
        org_pubkey: "",
        mesh_id: mesh,
        channel_kind: "dm-key-package-v1",
    }
}

pub(super) fn sign_key_package(
    identity: &ed25519_dalek::SigningKey,
    crypto: &MlsSessionCrypto,
    mesh: &str,
    payload: &[u8],
) -> Result<String, String> {
    let proof = SenderProof::sign(identity, crypto, &admission_context(mesh), payload.to_vec())?;
    Ok(encode(
        &serde_json::to_vec(&proof).map_err(|error| error.to_string())?,
    ))
}

impl PrivateDmSession {
    pub(super) fn expected_invitee(&self) -> Result<Option<String>, PrivateDmRuntimeError> {
        self.invite_uri
            .as_deref()
            .map(invite_ownership::target_peer)
            .transpose()
            .map(Option::flatten)
            .map_err(PrivateDmRuntimeError::InvalidInvite)
    }

    pub(super) fn accept_authenticated_key_package(
        &mut self,
        encoded: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let proof: SenderProof = decode_json(&decode(encoded)?)?;
        let sender = proof
            .verify(&admission_context(&self.mesh_id))
            .map_err(PrivateDmRuntimeError::InvalidInvite)?;
        let ControlEnvelope::KeyPackage {
            session_id,
            participant_id,
            key_package_b64,
            moss_peer_id,
            ..
        } = decode_json(&sender.payload)?
        else {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "admission proof requires a KeyPackage".into(),
            ));
        };
        if !self.is_alice_session(&session_id, &participant_id) {
            return Ok(());
        }
        let key_package = decode(&key_package_b64)?;
        if moss_peer_id.as_deref() != Some(&sender.peer_id)
            || self
                .expected_invitee()?
                .is_some_and(|expected| expected != sender.peer_id)
            || self.crypto.key_package_signer(&key_package)? != hex::encode(&sender.mls_signer)
        {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "KeyPackage identity differs from invitation target".into(),
            ));
        }
        let name = self.crypto.key_package_identity(&key_package)?;
        self.note_peer_name(&name);
        self.note_peer_moss_id(Some(sender.peer_id));
        self.answer_key_package(&key_package_b64)
    }
}

impl PrivateDmRuntime {
    pub(crate) fn create_targeted_invite(
        &mut self,
        request: StartSessionRequest,
        target: &str,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        let mut invite = self.create_invite(request)?;
        match self.authenticated_owned_invite(&invite.invite_uri, target) {
            Ok(uri) => invite.invite_uri = uri,
            Err(error) => {
                let _ = self.close_session(&invite.session_id);
                return Err(error);
            }
        }
        Ok(invite)
    }

    /// Save the intended installation before publishing its invitation.
    pub fn authenticated_owned_invite(
        &mut self,
        raw: &str,
        target: &str,
    ) -> Result<String, PrivateDmRuntimeError> {
        let (id, uri) = self.prepare_targeted_invite(raw, target)?;
        let previous = self.session_ref(&id)?.invite_uri.clone();
        self.session_mut(&id)?.invite_uri = Some(uri.clone());
        if let Err(error) = self.sessions.persist_record(&id, true) {
            self.session_mut(&id)?.invite_uri = previous;
            return Err(error.into());
        }
        Ok(uri)
    }

    fn prepare_targeted_invite(
        &self,
        raw: &str,
        target: &str,
    ) -> Result<(String, String), PrivateDmRuntimeError> {
        let invite = ParsedInvite::parse(raw)?;
        let session = self.session_ref(&invite.session_id)?;
        if !matches!(session.role, SessionRole::Alice)
            || session.crypto.member_count() != 1
            || invite.mesh_id != session.mesh_id
            || invite.fingerprint != session.crypto.fingerprint()
            || session
                .expected_invitee()?
                .is_some_and(|expected| expected != target)
        {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "offer requires an unadmitted creator and its original target".into(),
            ));
        }
        let owner = self.transport.local_peer_id().ok_or_else(|| {
            PrivateDmRuntimeError::InvalidInvite("creator identity unavailable".into())
        })?;
        let mut uri = url::Url::parse(&build_invite_uri(
            &session.mesh_id,
            &session.session_id,
            &session.crypto.fingerprint(),
            Some(&owner),
        ))
        .map_err(|error| PrivateDmRuntimeError::InvalidInvite(error.to_string()))?;
        uri.query_pairs_mut().append_pair("target", target);
        let uri = self
            .transport
            .authenticate_invite(uri.as_str(), &session.crypto)
            .map_err(PrivateDmRuntimeError::InvalidInvite)?;
        invite_ownership::verify_offered_invite(&uri, &owner, target)
            .map_err(PrivateDmRuntimeError::InvalidInvite)?;
        Ok((session.session_id.clone(), uri))
    }
}

pub(super) fn admission_key_package(
    payload: &[u8],
    mesh: &str,
) -> Result<Option<Vec<u8>>, PrivateDmRuntimeError> {
    let mut envelope: ControlEnvelope = decode_json(payload)?;
    if let ControlEnvelope::AuthenticatedKeyPackage { proof_b64, .. } = envelope {
        let proof: SenderProof = decode_json(&decode(&proof_b64)?)?;
        let sender = proof
            .verify(&admission_context(mesh))
            .map_err(PrivateDmRuntimeError::InvalidInvite)?;
        envelope = decode_json(&sender.payload)?;
    }
    match envelope {
        ControlEnvelope::KeyPackage {
            key_package_b64, ..
        } => Ok(Some(decode(&key_package_b64)?)),
        _ => Ok(None),
    }
}

#[cfg(test)]
#[path = "admission_authentication_tests.rs"]
mod tests;
