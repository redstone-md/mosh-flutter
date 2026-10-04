use super::super::*;
use super::{invalid, proof::DevicePacket, types::*, DEVICE_CHANNEL, RETRY_MS};
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
        if let Err(error) = self.reconcile_revocations(&identity) {
            device_error("revocation", error);
        }
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
        let Ok(identity) = link.identity(store.clone()) else {
            return;
        };
        let mut packets = Vec::new();
        for session in self.sessions.values_mut() {
            if session.device_signer.is_none() {
                continue;
            }
            if let Ok(recovery) = session.recovery_packets(&store, now) {
                packets.extend(recovery);
            }
            packets.extend(session.device_packets(&identity));
            packets.extend(session.removal_packets());
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
            DeviceMessage::Removal(evidence) => {
                self.receive_removal(&identity, &sender, &packet.roster, evidence)
            }
            DeviceMessage::RemovalAck {
                session_id,
                epoch,
                evidence,
            } => self.acknowledge_removal(&sender, &packet.roster, &session_id, epoch, &evidence),
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
            DeviceMessage::HistoryRequest(request) => {
                self.receive_history_request(&identity, &sender, &packet.roster, request)
            }
            DeviceMessage::HistoryBatch(batch) => {
                self.receive_history_batch(&identity, &sender, &packet.roster, batch)
            }
            DeviceMessage::RecoveryProbe(probe) => {
                self.receive_recovery_probe(&identity, &sender, &packet.roster, probe)
            }
            DeviceMessage::RecoveryOffer(offer) => {
                self.receive_recovery_offer(&identity, &sender, &packet.roster, offer)
            }
            DeviceMessage::RecoveryPull(pull) => {
                self.receive_recovery_pull(&identity, &sender, &packet.roster, pull)
            }
            DeviceMessage::RecoveryBatch(batch) => {
                self.receive_recovery_batch(&identity, &sender, &packet.roster, batch)
            }
            DeviceMessage::RecoveryEpoch(epoch) => {
                self.receive_recovery_epoch(&identity, &sender, &packet.roster, epoch)
            }
            DeviceMessage::RecoveryRemoval(removal) => {
                self.receive_recovery_removal(&identity, &sender, &packet.roster, removal)
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
