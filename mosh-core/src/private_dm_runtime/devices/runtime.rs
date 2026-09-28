use super::super::*;
use super::types::DmOffer;
use super::{
    invalid,
    proof::{DevicePacket, IdentityClaim},
    types::*,
    DEVICE_CHANNEL, INITIAL_CLIENTS, RETRY_MS,
};
use crate::device_link::identity::DeviceIdentity;
use crate::shared_node::SharedMossNode;
use std::sync::Arc;

pub(in crate::private_dm_runtime) struct DeviceDmLink {
    shared: Arc<SharedMossNode>,
    held: bool,
    last_pump: u64,
}

impl DeviceDmLink {
    pub fn new(shared: Arc<SharedMossNode>) -> Self {
        Self {
            shared,
            held: false,
            last_pump: 0,
        }
    }

    fn identity(&mut self, store: Arc<Persistence>) -> Result<DeviceIdentity> {
        if self.shared.current().is_none() {
            if store.get_device_link()?.is_none() {
                return Err(invalid());
            }
            self.shared.acquire(0, None).map_err(|_| invalid())?;
            self.held = true;
        }
        let node = self.shared.current().ok_or_else(invalid)?;
        // Start readers promptly for recently connected device streams.
        node.register_stream_handler(crate::stream_transport::ATTACHMENT_STREAM_ID)
            .map_err(|_| invalid())?;
        DeviceIdentity::open(store, &node.public_key_hex().ok_or_else(invalid)?)
            .map_err(|_| invalid())
    }
}

impl Drop for DeviceDmLink {
    fn drop(&mut self) {
        if self.held {
            self.shared.release();
        }
    }
}

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime) fn prepare_devices(&mut self) {
        for session in self.sessions.values_mut() {
            session.device_signer = None;
        }
        let Some(store) = self.sessions.persistence().cloned() else {
            return;
        };
        let Some(link) = self.device_link.as_mut() else {
            return;
        };
        let Ok(identity) = link.identity(store.clone()) else {
            return;
        };
        for session in self.sessions.values_mut() {
            session.device_store = Some(store.clone());
            if let Err(error) = session.refresh_device_identity(&identity) {
                device_error(&session.session_id, error);
            }
        }
    }

    pub(in crate::private_dm_runtime) fn pump_devices(&mut self, now: u64) {
        let Some(link) = self.device_link.as_mut() else {
            return;
        };
        if now.saturating_sub(link.last_pump) < RETRY_MS {
            return;
        }
        link.last_pump = now;
        let Some(store) = self.sessions.persistence().cloned() else {
            return;
        };
        let Ok(identity) = link.identity(store) else {
            return;
        };
        let mut packets = Vec::new();
        for session in self.sessions.values_mut() {
            if session.device_signer.is_none() {
                continue;
            }
            packets.extend(session.device_packets(&identity));
            session.publish_identity_claim(&identity);
        }
        for (peer, message) in packets {
            let _ = send_packet(&self.transport, &identity, &peer, message);
        }
    }

    pub(in crate::private_dm_runtime) fn receive_device_packet(
        &mut self,
        bytes: &[u8],
    ) -> Result<()> {
        if self.device_link.is_none() {
            return Err(invalid());
        }
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let peer = self.transport.local_peer_id().ok_or_else(invalid)?;
        let identity = DeviceIdentity::open(store, &peer).map_err(|_| invalid())?;
        let packet = DevicePacket::open(bytes, &peer)?;
        let sender = packet.device()?;
        match packet.message {
            DeviceMessage::Offer(offer) => {
                if packet.roster.digest().map_err(|_| invalid())?
                    != identity.roster().digest().map_err(|_| invalid())?
                {
                    return Err(invalid());
                }
                self.receive_device_offer(&identity, &sender, offer)
            }
            DeviceMessage::Join(request) => self.authorize_device_join(&identity, &sender, request),
            DeviceMessage::Admission(admission) => {
                self.apply_device_admission(&identity, &sender, &packet.roster, admission)
            }
            DeviceMessage::Ack {
                session_id,
                request_id,
                epoch,
            } => self.acknowledge_device_admission(
                &sender,
                &packet.roster,
                &session_id,
                &request_id,
                epoch,
            ),
        }
    }
}

impl PrivateDmSession {
    fn refresh_device_identity(&mut self, identity: &DeviceIdentity) -> Result<()> {
        let claim = IdentityClaim::create(
            identity,
            &self.session_id,
            &self.crypto.signer_public(),
            &self.device_id,
        )?;
        if self.membership.is_none() {
            self.membership = Some(DeviceMembership {
                topology: DmTopology {
                    own_user_id: identity.roster().user_id(),
                    clients: Vec::new(),
                    rosters: Vec::new(),
                },
                joining: None,
                delivery: None,
                receipt_targets: HashMap::new(),
                delivered_ids: Vec::new(),
            });
        }
        let membership = self.membership.as_mut().ok_or_else(invalid)?;
        if membership.topology.own_user_id != identity.roster().user_id() {
            return Err(invalid());
        }
        let changed = membership
            .topology
            .client(&claim.mls_signer)
            .map(|old| old.roster.digest())
            .transpose()
            .map_err(|_| invalid())?
            != Some(claim.roster.digest().map_err(|_| invalid())?);
        if changed {
            membership.topology.add_client(claim)?;
            self.record_dirty = true;
        }
        self.device_signer = Some(identity.key());
        Ok(())
    }

    fn publish_identity_claim(&mut self, identity: &DeviceIdentity) {
        if !self.peer_joined {
            return;
        }
        let Ok(claim) = IdentityClaim::create(
            identity,
            &self.session_id,
            &self.crypto.signer_public(),
            &self.device_id,
        ) else {
            return;
        };
        let Ok(body) = serde_json::to_vec(&claim) else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(&body) else {
            return;
        };
        let envelope = ControlEnvelope::DeviceIdentity {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            ciphertext_b64: encode(&ciphertext),
        };
        if let Ok(payload) = serde_json::to_vec(&envelope) {
            let _ = self.route_send(ChannelKind::Control, &payload);
        }
    }

    pub(in crate::private_dm_runtime) fn accept_identity_claim(
        &mut self,
        ciphertext: &str,
    ) -> Result<()> {
        let (body, signer) = self.crypto.decrypt_with_signer(&decode(ciphertext)?)?;
        let claim: IdentityClaim = decode_json(&body)?;
        claim.verify(&self.session_id)?;
        if claim.mls_signer != hex::encode(signer) {
            return Err(invalid());
        }
        let membership = self.membership.as_mut().ok_or_else(invalid)?;
        if let Some(existing) = membership.topology.client(&claim.mls_signer) {
            if existing.roster.user_id() != claim.roster.user_id() {
                return Err(invalid());
            }
        } else if self.crypto.member_count() != INITIAL_CLIENTS
            || claim.roster.user_id() == membership.topology.own_user_id
        {
            return Err(invalid());
        }
        let own = claim.roster.user_id() == membership.topology.own_user_id;
        membership.topology.add_client(claim.clone())?;
        self.record_dirty = true;
        if !own {
            self.note_peer_name(&claim.display_name);
            self.note_authenticated_frame(&claim.display_name);
        }
        Ok(())
    }

    fn device_packets(&self, identity: &DeviceIdentity) -> Vec<(String, DeviceMessage)> {
        let Some(membership) = &self.membership else {
            return Vec::new();
        };
        if let Some(join) = &membership.joining {
            return vec![(
                join.authorizer_peer.clone(),
                DeviceMessage::Join(join.request.clone()),
            )];
        }
        if let Some(journal) = &membership.delivery {
            return journal
                .waiting
                .iter()
                .map(|peer| {
                    (
                        peer.clone(),
                        DeviceMessage::Admission(journal.admission.clone()),
                    )
                })
                .collect();
        }
        if !self.peer_joined
            || membership
                .topology
                .validate(&self.session_id, &self.crypto.member_signers())
                .is_err()
        {
            return Vec::new();
        }
        let Ok(devices) = identity.roster().devices() else {
            return Vec::new();
        };
        let offer = self.device_offer(membership);
        devices
            .into_iter()
            .filter(|device| {
                !membership
                    .topology
                    .clients
                    .iter()
                    .any(|client| client.device_id == device.device_id)
            })
            .map(|device| (device.moss_peer_id, DeviceMessage::Offer(offer.clone())))
            .collect()
    }

    fn device_offer(&self, membership: &DeviceMembership) -> DmOffer {
        DmOffer {
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            fingerprint: self.fingerprint.clone(),
            invite_uri: self.invite_uri.clone(),
            group_id: self.crypto.group_id_bytes().unwrap_or_default(),
            own_name: self.device_id.clone(),
            peer_name: self.peer_display_name.clone().unwrap_or_default(),
            topology: membership.topology.clone(),
        }
    }
}

pub(super) fn send_packet(
    transport: &Arc<dyn DmTransport>,
    identity: &DeviceIdentity,
    peer: &str,
    message: DeviceMessage,
) -> Result<()> {
    transport.connect_peer(peer).map_err(|_| invalid())?;
    if transport.reach(peer) == PeerTransport::None {
        return Err(invalid());
    }
    let packet = DevicePacket::seal(identity, peer, message)?;
    let framed =
        crate::stream_transport::frame_for_channel(DEVICE_CHANNEL, &packet).ok_or_else(invalid)?;
    transport
        .send_to_peer_stream(peer, &framed)
        .map_err(|_| invalid())
}

pub(super) fn device_error(session: &str, error: PrivateDmRuntimeError) {
    dlog::write(LogLevel::Warn, kinds::VERIFY, session, &error.to_string());
}
