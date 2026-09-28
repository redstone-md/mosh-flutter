use super::super::*;
use super::{invalid, proof::verify, types::Result, NO_DEVICE_PEERS};
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};

const TEXT_CONTEXT: &[u8] = b"mosh-dm-text-v1\0";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct DeviceSignature {
    device_id: String,
    signature: String,
}

fn signing_bytes(envelope: &DataEnvelope, device: &str) -> Result<Vec<u8>> {
    let mut bytes = TEXT_CONTEXT.to_vec();
    bytes.extend(
        serde_json::to_vec(&(
            &envelope.session_id,
            &envelope.participant_id,
            &envelope.from_device,
            &envelope.message_id,
            &envelope.sent_at_ms,
            &envelope.ciphertext_b64,
            device,
        ))
        .map_err(|_| invalid())?,
    );
    Ok(bytes)
}

impl PrivateDmSession {
    pub(in crate::private_dm_runtime) fn devices_live(&self) -> bool {
        self.membership
            .as_ref()
            .is_some_and(|membership| membership.live())
    }

    pub(in crate::private_dm_runtime) fn sign_device_text(
        &self,
        envelope: &mut DataEnvelope,
    ) -> Result<()> {
        if !self.devices_live() {
            return Ok(());
        }
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let client = membership
            .client(&hex::encode(self.crypto.signer_public()))
            .ok_or_else(invalid)?;
        let key = self.device_signer.as_ref().ok_or_else(invalid)?;
        envelope.device_signature = Some(DeviceSignature {
            device_id: client.device_id.clone(),
            signature: hex::encode(
                key.sign(&signing_bytes(envelope, &client.device_id)?)
                    .to_bytes(),
            ),
        });
        Ok(())
    }

    /// Authenticate ids before re-acknowledging a ciphertext already consumed by MLS.
    pub(in crate::private_dm_runtime) fn verify_device_text(
        &self,
        envelope: &DataEnvelope,
    ) -> Result<Option<String>> {
        if !self.devices_live() {
            return Ok(None);
        }
        let proof = envelope.device_signature.as_ref().ok_or_else(invalid)?;
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let client = membership
            .topology
            .clients
            .iter()
            .find(|client| client.device_id == proof.device_id)
            .ok_or_else(invalid)?;
        verify(
            &client.device()?.signing_public_key,
            &proof.signature,
            &signing_bytes(envelope, &proof.device_id)?,
        )?;
        Ok(Some(client.mls_signer.clone()))
    }

    pub(in crate::private_dm_runtime) fn device_author(
        &self,
        signer: &[u8],
    ) -> Result<(String, bool)> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let signer = hex::encode(signer);
        let client = membership.client(&signer).ok_or_else(invalid)?;
        let own = membership.topology.own(&signer);
        Ok((
            if own {
                self.device_id.clone()
            } else {
                self.peer_display_name
                    .clone()
                    .unwrap_or_else(|| client.display_name.clone())
            },
            own,
        ))
    }

    /// Contact controls cannot turn activity on our other device into contact proof.
    pub(in crate::private_dm_runtime) fn decrypt_contact_control(
        &mut self,
        ciphertext: &[u8],
        legacy_author: &str,
    ) -> Result<Option<(Vec<u8>, String)>> {
        let (body, signer) = self.crypto.decrypt_with_signer(ciphertext)?;
        let author = if self.devices_live() {
            let (author, own) = self.device_author(&signer)?;
            if own {
                return Ok(None);
            }
            author
        } else {
            legacy_author.into()
        };
        Ok(Some((body, author)))
    }

    pub(in crate::private_dm_runtime) fn route_device_frame(
        &self,
        channel: &str,
        payload: &[u8],
    ) -> Result<()> {
        self.persist_device_crypto()?;
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        let own_signer = hex::encode(self.crypto.signer_public());
        let frame =
            crate::stream_transport::frame_for_channel(channel, payload).ok_or_else(invalid)?;
        let mut sent = false;
        for client in &membership.topology.clients {
            if client.mls_signer == own_signer {
                continue;
            }
            let peer = client.device()?.moss_peer_id;
            if self.transport.reach(&peer) != PeerTransport::None
                && self.transport.send_to_peer_stream(&peer, &frame).is_ok()
            {
                sent = true;
            }
        }
        if sent {
            Ok(())
        } else {
            Err(PrivateDmRuntimeError::Moss(NO_DEVICE_PEERS.into()))
        }
    }

    pub(in crate::private_dm_runtime) fn persist_device_crypto(&self) -> Result<()> {
        if self.membership.is_none() {
            return Ok(());
        }
        let Some(store) = &self.device_store else {
            return Ok(());
        };
        let record = serde_json::to_vec(&self.to_persisted_record()).map_err(|_| invalid())?;
        store.put_dm_transition(&self.session_id, &record, &self.crypto.snapshot())?;
        Ok(())
    }

    pub(in crate::private_dm_runtime) fn connect_devices(&mut self) {
        let Some(membership) = &self.membership else {
            return;
        };
        let local = hex::encode(self.crypto.signer_public());
        for client in &membership.topology.clients {
            if client.mls_signer == local {
                continue;
            }
            if let Ok(device) = client.device() {
                if !self.device_connect_requested.contains(&device.moss_peer_id)
                    && self.transport.connect_peer(&device.moss_peer_id).is_ok()
                {
                    self.device_connect_requested.insert(device.moss_peer_id);
                }
            }
        }
    }

    pub(in crate::private_dm_runtime) fn peer_device_reach(&self) -> Option<PeerTransport> {
        let membership = self
            .membership
            .as_ref()
            .filter(|membership| membership.live())?;
        let reaches = membership
            .topology
            .clients
            .iter()
            .filter(|client| !membership.topology.own(&client.mls_signer))
            .filter_map(|client| client.device().ok())
            .map(|device| self.transport.reach(&device.moss_peer_id));
        Some(
            reaches.fold(PeerTransport::None, |best, reach| match (best, reach) {
                (PeerTransport::Direct, _) | (_, PeerTransport::Direct) => PeerTransport::Direct,
                (PeerTransport::Relayed, _) | (_, PeerTransport::Relayed) => PeerTransport::Relayed,
                _ => PeerTransport::None,
            }),
        )
    }

    pub(in crate::private_dm_runtime) fn device_outbox_ready(&self) -> bool {
        !self.devices_live()
            || (self.state == DmSessionState::Connected
                && self
                    .membership
                    .as_ref()
                    .is_some_and(|membership| membership.delivery.is_none()))
    }
}
