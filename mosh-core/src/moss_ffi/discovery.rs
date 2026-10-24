use super::*;

impl MossNode {
    /// An older runtime retains automatic discovery when this optional symbol
    /// is absent. Empty recipients explicitly restore that default.
    pub fn set_room_known_peers(&self, room: &str, peers: &[String]) -> Result<(), MossFfiError> {
        let Some(operation) = self.runtime.set_room_peer_discovery else {
            return Ok(());
        };
        let room = c_string(room)?;
        // String slices serialize infallibly; propagate allocation/serializer
        // failures through the adapter's existing runtime error boundary.
        let json = serde_json::to_string(peers)
            .map_err(|error| MossFfiError::Runtime(MossRuntimeError::Load(error.to_string())))?;
        let peers_json = c_string(&json)?;
        // SAFETY: the optional symbol uses Moss's int64/int32/pointer C ABI;
        // both CStrings and the loaded library live throughout this call.
        check_code("set_room_peer_discovery", unsafe {
            operation(
                self.handle,
                room.as_ptr(),
                i32::from(!peers.is_empty()),
                peers_json.as_ptr(),
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn room_discovery_round_trips_and_propagates_native_validation() {
        let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
        assert!(
            runtime.set_room_peer_discovery.is_some(),
            "test requires the pinned Moss library"
        );
        let config = MossNodeConfig {
            listen_port: 0,
            static_peer: None,
            bind_interface: None,
        };
        let node = runtime
            .init_default_node("discovery-room", &config)
            .unwrap();
        node.set_room_known_peers("discovery-room", &["ab".repeat(32)])
            .unwrap();
        node.set_room_known_peers("discovery-room", &[]).unwrap();
        assert!(node
            .set_room_known_peers("missing-room", &["ab".repeat(32)])
            .is_err());
        assert!(node
            .set_room_known_peers("discovery-room", &["invalid".into()])
            .is_err());
        assert!(node.set_room_known_peers("invalid\0room", &[]).is_err());
    }
}
