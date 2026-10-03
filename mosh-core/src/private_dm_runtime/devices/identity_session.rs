//! Bind linked MLS clients to the signed installation roster.

use super::super::*;
use super::types::DmOffer;
use super::{invalid, proof::IdentityClaim, types::*, INITIAL_CLIENTS};
use crate::device_link::identity::DeviceIdentity;

impl PrivateDmSession {
    pub(super) fn current_device_claim(&self, identity: &DeviceIdentity) -> Result<IdentityClaim> {
        let current = self
            .membership
            .as_ref()
            .and_then(|membership| membership.topology.roster(&identity.roster().user_id()));
        let pending = self.membership.as_ref().is_some_and(|m| {
            m.pending_removal()
                || current.is_some_and(|roster| {
                    identity.roster().has_removal_since(roster).unwrap_or(false)
                })
                || m.topology.clients.iter().any(|c| {
                    c.roster.user_id() == identity.roster().user_id()
                        && identity
                            .roster()
                            .revoked_since(&c.roster, &c.device_id)
                            .unwrap_or(false)
                })
        });
        let roster = match current {
            Some(roster) if pending => roster,
            Some(roster) if roster.extends(identity.roster()).map_err(|_| invalid())? => roster,
            _ => identity.roster(),
        };
        IdentityClaim::create_with_roster(
            identity,
            roster,
            &self.session_id,
            &self.crypto.signer_public(),
            &self.device_id,
        )
    }

    pub(super) fn refresh_device_identity(&mut self, identity: &DeviceIdentity) -> Result<()> {
        if self.membership.as_ref().is_some_and(|m| m.revoked) {
            return Ok(());
        }
        let claim = self.current_device_claim(identity)?;
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
                history_import: None,
                history_exports: Vec::new(),
                recovery: None,
                recovery_exports: Vec::new(),
                epoch_records: Vec::new(),
                removals: Vec::new(),
                revoked: false,
                pending_rosters: Vec::new(),
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

    pub(super) fn publish_identity_claim(&mut self, identity: &DeviceIdentity) {
        if !self.peer_joined {
            return;
        }
        let Ok(claim) = self.current_device_claim(identity) else {
            return;
        };
        let Ok(ciphertext_b64) = self.crypto.encrypt_json(&claim) else {
            return;
        };
        let envelope = ControlEnvelope::DeviceIdentity {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            ciphertext_b64,
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
        if membership.observe_roster_removal(&claim.roster)? {
            self.record_dirty = true;
            return Ok(());
        }
        if membership.current_roster(&claim.roster.user_id()).is_some()
            && !membership.authorized(&claim.device()?, &claim.roster.user_id())
        {
            return Err(invalid());
        }
        membership.topology.add_client(claim.clone())?;
        self.record_dirty = true;
        if !own {
            self.note_peer_name(&claim.display_name);
            self.note_authenticated_frame(&claim.display_name);
        }
        Ok(())
    }

    pub(super) fn device_packets(&self, identity: &DeviceIdentity) -> Vec<(String, DeviceMessage)> {
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
        let mut packets: Vec<_> = devices
            .into_iter()
            .filter(|device| {
                !membership
                    .topology
                    .clients
                    .iter()
                    .any(|client| client.device_id == device.device_id)
            })
            .map(|device| (device.moss_peer_id, DeviceMessage::Offer(offer.clone())))
            .collect();
        packets.extend(self.history_request());
        packets
    }

    pub(super) fn device_offer(&self, membership: &DeviceMembership) -> DmOffer {
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
