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
