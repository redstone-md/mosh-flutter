use super::*;

impl MemoryNet {
    /// Use real identity signatures while retaining transport fault controls.
    pub fn authenticated_endpoint(
        self: &Arc<Self>,
        identity: &ed25519_dalek::SigningKey,
    ) -> Arc<MemoryTransport> {
        let peer = crate::org_signing::peer_id_hex(identity);
        let mut endpoint = self.endpoint(&peer);
        Arc::get_mut(&mut endpoint).unwrap().identity = Some(identity.clone());
        endpoint
    }
}
