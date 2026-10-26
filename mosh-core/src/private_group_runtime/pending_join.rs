//! Resume an org acceptance with the original MLS identity and Welcome target.

use super::*;
use crate::org_runtime::PendingJoinRecovery;

#[derive(Default)]
pub(super) struct JoinRetry {
    next: Option<std::time::Instant>,
    attempts: u8,
    last_attempt: Option<std::time::Instant>,
    peer_revision: u64,
}

impl GroupSession {
    pub(super) fn retry_pending_join(&mut self) -> Result<(), PrivateGroupError> {
        let now = std::time::Instant::now();
        let route_changed = self.join_retry.peer_revision
            != crate::moss_ffi::connected_peer_revision()
            && self
                .join_retry
                .last_attempt
                .is_none_or(|last| now.duration_since(last).as_secs() >= 3);
        if route_changed || self.join_retry.next.is_none_or(|at| now >= at) {
            self.publish_pending_join()?;
        }
        Ok(())
    }

    fn publish_pending_join(&mut self) -> Result<(), PrivateGroupError> {
        let Some(package) = self.pending_join_package.as_ref().filter(|_| !self.joined) else {
            return Ok(());
        };
        // Retain the original KeyPackage, signer and target. A retry must not
        // create another leaf or make a previously issued Welcome unusable.
        let result = publish_join_package(
            &self.node,
            &self.to_persisted_record(),
            package,
            &self.crypto,
            self.org_signer.as_ref(),
        );
        // An empty topic is a discovery wait, not a delivered join attempt.
        // Probe it at most once per three seconds without escalating to a
        // minute-long retry after the first subscribers finally appear.
        let delay = if matches!(result, Ok(false)) {
            self.join_retry.attempts = 0;
            3
        } else {
            let delay = (3u64 << self.join_retry.attempts.min(5)).min(60);
            self.join_retry.attempts = self.join_retry.attempts.saturating_add(1);
            delay
        };
        let now = std::time::Instant::now();
        self.join_retry.last_attempt = Some(now);
        self.join_retry.peer_revision = crate::moss_ffi::connected_peer_revision();
        self.join_retry.next = Some(now + std::time::Duration::from_secs(delay));
        result.map(|_| ())
    }
}

struct JoinPreparation {
    request: JoinGroupRequest,
    invite: ParsedGroupInvite,
    crypto: MlsSessionCrypto,
    org_signer: Option<SigningKey>,
    participant_id: String,
    key_package: Option<Vec<u8>>,
}

impl JoinPreparation {
    fn new(
        request: JoinGroupRequest,
        invite: ParsedGroupInvite,
        recovery: Option<(Vec<u8>, PendingJoinRecovery)>,
        store: Option<&Persistence>,
    ) -> Result<Self, PrivateGroupError> {
        let org_signer = request
            .org_pubkey
            .as_ref()
            .map(|_| load_org_signer(store))
            .transpose()?;
        let identity = org_signer
            .as_ref()
            .map(org_signing::peer_id_hex)
            .unwrap_or_else(|| request.display_name.clone());
        let prepared = PendingJoinRecovery::prepare(&identity, recovery)?;
        Ok(Self {
            request,
            invite,
            crypto: prepared.crypto,
            org_signer,
            participant_id: prepared.participant_id,
            key_package: prepared.key_package,
        })
    }

    fn record(&self, device_fingerprint: String) -> PersistedGroupSession {
        PersistedGroupSession {
            group_id: self.invite.group_id.clone(),
            mesh_id: self.invite.mesh_id.clone(),
            label: self.invite.label.clone(),
            names: Default::default(),
            display_name: self.request.display_name.clone(),
            participant_id: self.participant_id.clone(),
            device_fingerprint,
            creator_fingerprint: self.invite.creator_fingerprint.clone(),
            current_admin_fingerprint: self.invite.creator_fingerprint.clone(),
            is_admin: false,
            invite_uri: Some(self.request.invite_uri.clone()),
            joined: self.crypto.is_ready(),
            signer_public: self.crypto.signer_public(),
            mls_group_id: self.crypto.group_id_bytes().unwrap_or_default(),
            listen_port: self.request.listen_port,
            static_peer: self.request.static_peer.clone(),
            org_pubkey: self.request.org_pubkey.clone(),
        }
    }
}

impl PrivateGroupRuntime {
    pub(crate) fn join_recovery(
        &mut self,
        id: &str,
    ) -> Result<PendingJoinRecovery, PrivateGroupError> {
        let session = self.group_mut(id)?;
        Ok(PendingJoinRecovery {
            provider_snapshot: session.crypto.snapshot(),
            participant_id: session.participant_id.clone(),
            mls_group_id: session.crypto.group_id_bytes().unwrap_or_default(),
            key_package: session.pending_join_package.clone(),
        })
    }

    pub(crate) fn join_group_restoring(
        &mut self,
        request: JoinGroupRequest,
        recovery: Option<(Vec<u8>, PendingJoinRecovery)>,
    ) -> Result<GroupSnapshot, PrivateGroupError> {
        let id = self.prepare_group_restoring(request, recovery)?;
        if let Err(error) = self.publish_prepared_join(&id) {
            self.discard_prepared_join(&id);
            return Err(error);
        }
        self.poll(&id)
    }

    /// Hold the prepared session while org recovery intent becomes durable.
    pub(crate) fn prepare_group_restoring(
        &mut self,
        request: JoinGroupRequest,
        recovery: Option<(Vec<u8>, PendingJoinRecovery)>,
    ) -> Result<String, PrivateGroupError> {
        let invite = ParsedGroupInvite::parse(&request.invite_uri)?;
        if self.groups.holds(&invite.group_id) {
            return Err(PrivateGroupError::DuplicateGroup(invite.group_id));
        }
        let preparation = JoinPreparation::new(
            request,
            invite,
            recovery,
            self.groups.persistence().map(Arc::as_ref),
        )?;
        let session = self.open_joining_session(preparation)?;
        let id = session.group_id.clone();
        self.groups.insert(id.clone(), session);
        Ok(id)
    }

    pub(crate) fn publish_prepared_join(&mut self, id: &str) -> Result<(), PrivateGroupError> {
        self.group_mut(id)?.publish_pending_join()
    }

    /// A prepared join has no new durable rows to delete on rollback.
    pub(crate) fn discard_prepared_join(&mut self, id: &str) {
        if let Some(session) = self.groups.remove(id) {
            runtime::close_room(
                &self.shared_node,
                &session.node,
                &session.mesh_id,
                &group_channels(id),
                &format!("{KIND} {id}"),
            );
        }
        self.groups.forget(id);
    }

    fn open_joining_session(
        &mut self,
        prepared: JoinPreparation,
    ) -> Result<GroupSession, PrivateGroupError> {
        let mesh = prepared.invite.mesh_id.clone();
        let id = prepared.invite.group_id.clone();
        let node = self.open_group_room(
            &mesh,
            &id,
            prepared.request.listen_port,
            prepared.request.static_peer.clone(),
        )?;
        let result = (|| {
            let fingerprint = node
                .public_key_hex()
                .ok_or_else(|| PrivateGroupError::Moss("public key unavailable".into()))?;
            let record = prepared.record(fingerprint);
            let mut session = GroupSession::new(
                record,
                node.clone(),
                prepared.crypto,
                self.groups.persistence().cloned(),
                Arc::clone(self.groups.attachment_store()),
                prepared.org_signer,
            );
            session.pending_join_package = prepared.key_package;
            Ok(session)
        })();
        if result.is_err() {
            runtime::close_room(
                &self.shared_node,
                &node,
                &mesh,
                &group_channels(&id),
                &format!("{KIND} {id}"),
            );
        }
        result
    }
}

fn publish_join_package(
    node: &MossNode,
    record: &PersistedGroupSession,
    package: &[u8],
    crypto: &MlsSessionCrypto,
    signer: Option<&SigningKey>,
) -> Result<bool, PrivateGroupError> {
    let envelope = ControlEnvelope::KeyPackage {
        joiner_binding: Some(super::history::admission::joiner_binding(
            node, crypto, record, package,
        )?),
        group_id: record.group_id.clone(),
        participant_id: record.participant_id.clone(),
        from_device: record.display_name.clone(),
        from_fingerprint: record.device_fingerprint.clone(),
        key_package_b64: encode(package),
    };
    let payload = super::wires::control_payload(
        &format!("{CONTROL_CHANNEL_PREFIX}{}", record.group_id),
        &record.mesh_id,
        org_context(record.org_pubkey.as_deref(), signer),
        &envelope,
    )?;
    match node.publish_room(
        &record.mesh_id,
        &format!("{CONTROL_CHANNEL_PREFIX}{}", record.group_id),
        &payload,
    ) {
        Ok(()) => Ok(true),
        Err(error) if error.is_no_peers() => Ok(false),
        Err(error) => Err(PrivateGroupError::Moss(error.to_string())),
    }
}
