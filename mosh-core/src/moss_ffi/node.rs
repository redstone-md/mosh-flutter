//! Node lifecycle and room operations. Publish refusals keep their existing classification.
use super::*;

impl MossNode {
    pub fn subscribe(&self, channel: &str) -> Result<(), MossFfiError> {
        self.call_string("subscribe", self.runtime.subscribe, channel)
    }

    pub fn unsubscribe(&self, channel: &str) -> Result<(), MossFfiError> {
        self.call_string("unsubscribe", self.runtime.unsubscribe, channel)
    }

    pub fn leave_room(&self, mesh_id: &str) -> Result<(), MossFfiError> {
        self.call_string("leave_room", self.runtime.leave_room, mesh_id)
    }

    pub fn connect(&self, address: &str) -> Result<(), MossFfiError> {
        self.call_string("connect", self.runtime.connect, address)
    }

    pub fn connect_to_peer(&self, peer_id_hex: &str) -> Result<(), MossFfiError> {
        self.call_string("connect_to_peer", self.runtime.connect_to_peer, peer_id_hex)
    }

    pub fn start(&self) -> Result<(), MossFfiError> {
        check_code("start", unsafe { (self.runtime.start)(self.handle) })
    }

    pub fn join_room(&self, mesh_id: &str) -> Result<(), MossFfiError> {
        let mesh_id = c_string(mesh_id)?;

        check_code("join_room", unsafe {
            (self.runtime.join_room)(self.handle, mesh_id.as_ptr(), std::ptr::null(), 0)
        })
    }

    pub fn publish_room(
        &self,
        mesh_id: &str,
        channel: &str,
        payload: &[u8],
    ) -> Result<(), MossFfiError> {
        #[cfg(test)]
        if let Some(outcome) = take_test_publish_outcome() {
            return outcome;
        }

        let mesh_id = c_string(mesh_id)?;
        let channel = c_string(channel)?;

        let published = check_publish_code(unsafe {
            (self.runtime.publish_room)(
                self.handle,
                mesh_id.as_ptr(),
                channel.as_ptr(),
                payload.as_ptr(),
                payload.len() as u32,
            )
        });
        #[cfg(test)]
        let published = tolerate_unmeshed_test_node(published);
        published
    }

    pub fn publish_room_best_effort(
        &self,
        mesh_id: &str,
        channel: &str,
        payload: &[u8],
    ) -> Result<(), MossFfiError> {
        match self.publish_room(mesh_id, channel, payload) {
            Err(error) if error.is_no_peers() => Ok(()),
            other => other,
        }
    }

    pub fn publish(&self, channel: &str, payload: &[u8]) -> Result<(), MossFfiError> {
        #[cfg(test)]
        if let Some(outcome) = take_test_publish_outcome() {
            return outcome;
        }

        let channel = c_string(channel)?;
        let code = unsafe {
            (self.runtime.publish)(
                self.handle,
                channel.as_ptr(),
                payload.as_ptr(),
                payload.len() as u32,
            )
        };

        let published = check_publish_code(code);
        #[cfg(test)]
        let published = tolerate_unmeshed_test_node(published);
        published
    }

    pub fn set_message_callback(&self) -> Result<(), MossFfiError> {
        check_code("set_callback", unsafe {
            (self.runtime.set_callback)(self.handle, Some(on_moss_message))
        })
    }

    pub fn set_event_callback(&self) -> Result<(), MossFfiError> {
        check_code("set_event_callback", unsafe {
            (self.runtime.set_event_callback)(self.handle, Some(on_moss_event))
        })
    }

    pub fn subscribe_room(&self, mesh_id: &str, channel: &str) -> Result<(), MossFfiError> {
        self.call_room_channel(
            "subscribe_room",
            self.runtime.subscribe_room,
            mesh_id,
            channel,
        )
    }

    pub fn unsubscribe_room(&self, mesh_id: &str, channel: &str) -> Result<(), MossFfiError> {
        self.call_room_channel(
            "unsubscribe_room",
            self.runtime.unsubscribe_room,
            mesh_id,
            channel,
        )
    }

    fn call_string(
        &self,
        name: &'static str,
        operation: MossSubscribe,
        value: &str,
    ) -> Result<(), MossFfiError> {
        let value = c_string(value)?;
        // SAFETY: CString lives through the call and all operations share this ABI.
        check_code(name, unsafe { operation(self.handle, value.as_ptr()) })
    }

    fn call_room_channel(
        &self,
        name: &'static str,
        operation: MossRoomChannel,
        mesh_id: &str,
        channel: &str,
    ) -> Result<(), MossFfiError> {
        let mesh_id = c_string(mesh_id)?;
        let channel = c_string(channel)?;
        // SAFETY: both CString arguments remain valid through the native call.
        check_code(name, unsafe {
            operation(self.handle, mesh_id.as_ptr(), channel.as_ptr())
        })
    }
}

impl Drop for MossNode {
    fn drop(&mut self) {
        unsafe {
            (self.runtime.stop)(self.handle);
        }
    }
}
