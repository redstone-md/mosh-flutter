//! Group creation and admission.

use super::*;

#[cfg(test)]
#[path = "lifecycle_tests.rs"]
mod tests;

impl PrivateGroupRuntime {
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

        let record = PersistedGroupSession {
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
            signer_public: crypto.signer_public(),
            mls_group_id: crypto.group_id_bytes().unwrap_or_default(),
            listen_port,
            static_peer,
            org_pubkey: request.org_pubkey,
        };
        let session = GroupSession::new(
            record,
            node,
            crypto,
            self.groups.persistence().cloned(),
            Arc::clone(self.groups.attachment_store()),
            org_signer,
        );

        self.persist_created_group(&session)?;
        self.groups.insert(group_id.clone(), session);
        self.groups.mark_record_final(&group_id);
        Ok(GroupCreated {
            group_id,
            mesh_id,
            invite_uri,
            fingerprint: creator_fingerprint,
            label,
        })
    }

    fn persist_created_group(&self, session: &GroupSession) -> Result<(), PrivateGroupError> {
        let Some(store) = self.groups.persistence() else {
            return Ok(());
        };
        if let Err(error) = session.write_extra(store) {
            runtime::close_room(
                &self.shared_node,
                &session.node,
                &session.mesh_id,
                &group_channels(&session.group_id),
                &format!("{KIND} {}", session.group_id),
            );
            return Err(error.into());
        }
        Ok(())
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
        let record = PersistedGroupSession {
            group_id: invite.group_id.clone(),
            mesh_id: invite.mesh_id,
            label: invite.label,
            display_name: request.display_name,
            participant_id,
            device_fingerprint,
            creator_fingerprint: invite.creator_fingerprint.clone(),
            current_admin_fingerprint: invite.creator_fingerprint,
            is_admin: false,
            invite_uri: Some(request.invite_uri),
            joined: false,
            signer_public: crypto.signer_public(),
            mls_group_id: crypto.group_id_bytes().unwrap_or_default(),
            listen_port,
            static_peer,
            org_pubkey: request.org_pubkey,
        };
        let session = GroupSession::new(
            record,
            node,
            crypto,
            self.groups.persistence().cloned(),
            Arc::clone(self.groups.attachment_store()),
            org_signer,
        );
        self.groups.insert(invite.group_id.clone(), session);
        self.poll(&invite.group_id)
    }
}
