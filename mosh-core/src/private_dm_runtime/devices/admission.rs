use super::super::*;
use super::types::DmOffer;
use super::{invalid, proof::IdentityClaim, runtime::send_packet, types::*};
use crate::device_link::{identity::DeviceIdentity, roster::DeviceRoster, types::DeviceDescriptor};

impl PrivateDmRuntime {
    pub(super) fn receive_device_offer(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        offer: DmOffer,
    ) -> Result<()> {
        if self.sessions.holds(&offer.session_id) && !self.can_rejoin_device(identity, &offer)? {
            return Ok(());
        }
        let signers: Vec<_> = offer
            .topology
            .clients
            .iter()
            .map(|client| client.mls_signer.clone())
            .collect();
        offer.topology.validate(&offer.session_id, &signers)?;
        if offer.topology.own_user_id != identity.roster().user_id()
            || !offer.topology.clients.iter().any(|client| {
                client.device_id == sender.device_id && offer.topology.own(&client.mls_signer)
            })
            || offer
                .topology
                .clients
                .iter()
                .any(|client| client.device_id == identity.device().device_id)
        {
            return Err(invalid());
        }
        let mut crypto = MlsSessionCrypto::new(&identity.device().device_id)?;
        let request = JoinRequest {
            request_id: crypto.random_token(JOIN_TOKEN)?,
            claim: IdentityClaim::create(
                identity,
                &offer.session_id,
                &crypto.signer_public(),
                &offer.own_name,
            )?,
            key_package: crypto.key_package_bytes()?,
        };
        let mut session = self.pending_device_session(offer, crypto, request.clone(), sender)?;
        self.restore_revoked_history(&mut session)?;
        self.persist_device_session(&session)?;
        self.sessions.mark_record_final(&session.session_id);
        self.sessions.insert(session.session_id.clone(), session);
        send_packet(
            &self.transport,
            identity,
            &sender.moss_peer_id,
            DeviceMessage::Join(request),
        )
    }

    fn pending_device_session(
        &mut self,
        offer: DmOffer,
        crypto: MlsSessionCrypto,
        request: JoinRequest,
        sender: &DeviceDescriptor,
    ) -> Result<PrivateDmSession> {
        self.open_dm_room(&offer.mesh_id, &offer.session_id, 0, None)?;
        let participant = crypto.random_token(PARTICIPANT_TOKEN)?;
        let mut session = PrivateDmSession::new(
            SessionRole::Bob,
            offer.own_name,
            participant,
            offer.session_id,
            offer.mesh_id,
            offer.fingerprint,
            offer.invite_uri,
            0,
            None,
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        session.peer_display_name = Some(offer.peer_name);
        session.peer_moss_id = offer
            .topology
            .clients
            .iter()
            .find(|client| !offer.topology.own(&client.mls_signer))
            .map(IdentityClaim::device)
            .transpose()?
            .map(|device| device.moss_peer_id);
        let history_import = super::history::HistoryImport::new(&request.request_id, sender);
        session.membership = Some(DeviceMembership {
            topology: offer.topology,
            joining: Some(PendingJoin {
                request,
                authorizer_peer: sender.moss_peer_id.clone(),
                group_id: offer.group_id,
            }),
            delivery: None,
            receipt_targets: HashMap::new(),
            delivered_ids: Vec::new(),
            history_import: Some(history_import),
            history_exports: Vec::new(),
            recovery: None,
            recovery_exports: Vec::new(),
            epoch_records: Vec::new(),
            removals: Vec::new(),
            revoked: false,
            pending_rosters: Vec::new(),
        });
        Ok(session)
    }

    pub(super) fn authorize_device_join(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        request: JoinRequest,
    ) -> Result<()> {
        let session_id = request.claim.session_id.clone();
        let session = self.session_ref(&session_id)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        verify_request(&session.crypto, &request)?;
        if sender.device_id != request.claim.device_id
            || request.claim.roster.digest().map_err(|_| invalid())?
                != identity.roster().digest().map_err(|_| invalid())?
            || identity.roster().user_id() != membership.topology.own_user_id
        {
            return Err(invalid());
        }
        if membership.client(&request.claim.mls_signer).is_some() || membership.delivery.is_some() {
            return Ok(());
        }
        membership
            .topology
            .validate(&session_id, &session.crypto.member_signers())?;
        let mut crypto = copy_crypto(session)?;
        let outcome = crypto.add_members(&[&request.key_package])?;
        let mut next = membership.clone();
        next.topology.add_client(request.claim.clone())?;
        next.topology
            .validate(&session_id, &crypto.member_signers())?;
        let mut admission = Admission {
            request,
            commit: outcome.commit_bytes,
            welcome: outcome.welcome_bytes,
            tree: outcome.tree_bytes,
            topology: next.topology.clone(),
            group_id: crypto.group_id_bytes().ok_or_else(invalid)?,
            epoch: crypto.epoch().ok_or_else(invalid)?,
            recovery_authorization: None,
        };
        let evidence = super::recovery::EpochRecord::create(identity, &admission, now_ms())?;
        admission.recovery_authorization = Some(evidence.authorization());
        next.retain_epoch(evidence)?;
        next.delivery = Some(AdmissionJournal::new(
            admission,
            &identity.device().device_id,
        )?);
        self.install_device_transition(&session_id, crypto, next)
    }

    pub(super) fn apply_device_admission(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        sender_roster: &DeviceRoster,
        admission: Admission,
    ) -> Result<()> {
        let session_id = admission.request.claim.session_id.clone();
        let session = self.session_ref(&session_id)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        verify_authorizer(membership, sender, sender_roster, &admission)?;
        membership.authorize_current_admission(
            identity,
            sender,
            sender_roster,
            &admission.request.claim,
        )?;
        verify_request(&session.crypto, &admission.request)?;
        let evidence =
            super::recovery::EpochRecord::from_admission(sender, sender_roster, &admission)?;
        if membership.joining.is_none()
            && session.crypto.epoch() == Some(admission.epoch)
            && membership
                .client(&admission.request.claim.mls_signer)
                .is_some()
        {
            return self.send_admission_ack(identity, sender, &admission);
        }
        let (crypto, mut next) = stage_admission(session, &admission)?;
        if let Some(evidence) = evidence {
            next.retain_epoch(evidence)?;
        }
        self.install_device_transition(&session_id, crypto, next)?;
        self.send_admission_ack(identity, sender, &admission)
    }

    pub(super) fn send_admission_ack(
        &self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        admission: &Admission,
    ) -> Result<()> {
        send_packet(
            &self.transport,
            identity,
            &sender.moss_peer_id,
            DeviceMessage::Ack {
                session_id: admission.request.claim.session_id.clone(),
                request_id: admission.request.request_id.clone(),
                epoch: admission.epoch,
            },
        )
    }

    pub(super) fn acknowledge_device_admission(
        &mut self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        session_id: &str,
        request: &str,
        epoch: u64,
    ) -> Result<()> {
        let session = self.session_ref(session_id)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        let base = membership
            .topology
            .roster(&roster.user_id())
            .ok_or_else(invalid)?;
        if !roster.extends(base).map_err(|_| invalid())?
            || !membership
                .topology
                .clients
                .iter()
                .any(|client| client.device_id == sender.device_id)
        {
            return Err(invalid());
        }
        let Some(journal) = &membership.delivery else {
            return Ok(());
        };
        if journal.admission.request.request_id != request || journal.admission.epoch != epoch {
            return Err(invalid());
        }
        let mut next = membership.clone();
        let journal = next.delivery.as_mut().ok_or_else(invalid)?;
        journal.waiting.retain(|peer| peer != &sender.moss_peer_id);
        if journal.accepted()? {
            next.delivery = None;
        }
        self.install_device_transition(session_id, copy_crypto(session)?, next)
    }

    pub(super) fn install_device_transition(
        &mut self,
        session_id: &str,
        crypto: MlsSessionCrypto,
        membership: DeviceMembership,
    ) -> Result<()> {
        let session = self.session_ref(session_id)?;
        let mut record = session.to_persisted_record();
        record.membership = Some(membership.clone());
        record.group_id = crypto.group_id_bytes().unwrap_or_default();
        self.save_device_transition(&record, &crypto)?;
        let session = self.session_mut(session_id)?;
        let epoch_changed = session.crypto.epoch() != crypto.epoch();
        session.crypto = crypto;
        session.membership = Some(membership);
        session.record_dirty = false;
        if epoch_changed {
            for attempt in session.outbound_attempts.values_mut() {
                attempt.last_send_ms = 0;
            }
            session.note_handshake_frame();
            session.state = DmSessionState::Handshaking;
            session.seen = SeenFrames::default();
        }
        Ok(())
    }

    fn persist_device_session(&self, session: &PrivateDmSession) -> Result<()> {
        self.save_device_transition(&session.to_persisted_record(), &session.crypto)
    }

    fn save_device_transition(
        &self,
        record: &contracts::PersistedSession,
        crypto: &MlsSessionCrypto,
    ) -> Result<()> {
        let store = self.sessions.persistence().ok_or_else(invalid)?;
        let bytes = serde_json::to_vec(record).map_err(|_| invalid())?;
        store.put_dm_transition(&record.session_id, &bytes, &crypto.snapshot())?;
        Ok(())
    }
}

const JOIN_TOKEN: &str = "device-join";
const PARTICIPANT_TOKEN: &str = "participant";
const MAX_REQUEST_ID_BYTES: usize = 128;

#[path = "admission_proof.rs"]
mod proof;
pub(super) use proof::{copy_crypto, stage_admission, verify_authorizer, verify_request};
