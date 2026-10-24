use super::super::*;

impl PrivateDmSession {
    /// Require an authenticated route for every current MLS client. Legacy
    /// address pins alone cannot establish that the recipient set is complete.
    fn room_recipients(&self) -> Option<Vec<String>> {
        let membership = self.membership.as_ref()?;
        if membership.revoked || membership.is_joining() {
            return None;
        }
        let signers = self.crypto.member_signers();
        if signers.len() < 2 || !membership.has_counterpart(&signers) {
            return None;
        }
        let local = hex::encode(self.crypto.signer_public());
        let mut recipients = Vec::new();
        for signer in signers {
            let peer = membership.call_peer(&signer)?;
            if signer != local {
                recipients.push(peer);
            }
        }
        recipients.sort();
        recipients.dedup();
        (!recipients.is_empty()).then_some(recipients)
    }

    pub(in crate::private_dm_runtime) fn refresh_room_discovery(&mut self) {
        let peers = self
            .room_recipients()
            .filter(|peers| {
                peers
                    .iter()
                    .all(|peer| self.device_connect_requested.contains(peer))
            })
            .unwrap_or_default();
        if self.room_discovery_peers.as_ref() == Some(&peers) {
            return;
        }
        match self.transport.set_room_known_peers(&self.mesh_id, &peers) {
            Ok(()) => self.room_discovery_peers = Some(peers),
            Err(error) => dlog::write(
                LogLevel::Warn,
                kinds::CONNECT,
                &self.session_id,
                &format!("could not update room discovery: {error}"),
            ),
        }
    }
}
