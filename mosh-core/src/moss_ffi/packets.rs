//! Directed packets use Moss's direct/relay routing, independent of room publication.

use super::*;

/// Synthetic inbox channels retain the callback's claimed sender key.
/// Authenticate application controls separately; this is not an identity proof.
pub const PACKET_INBOX_CHANNEL_PREFIX: &str = "moss-packet:";

impl MossNode {
    /// Register the directed packet sink without replacing Moss stream handlers.
    pub fn set_packet_callback(&self) -> Result<(), MossFfiError> {
        let register = self
            .runtime
            .set_packet_callback
            .ok_or_else(|| MossFfiError::Symbol("Moss_SetPacketCallback".into()))?;
        // SAFETY: the context-free function has the pinned MossPacketCallback ABI.
        check_code("set_packet_callback", unsafe {
            register(self.handle, Some(on_packet_payload))
        })
    }

    /// Send one opaque packet to the selected Moss peer. Success means admission,
    /// not delivery. The pinned FFI may spend up to five seconds opening a relay.
    pub fn send_to_peer(&self, peer: &str, payload: &[u8]) -> Result<(), MossFfiError> {
        let send = self
            .runtime
            .send_to_peer
            .ok_or_else(|| MossFfiError::Symbol("Moss_SendToPeer".into()))?;
        let peer = c_string(peer)?;
        let length = i32::try_from(payload.len()).map_err(|_| MossFfiError::Operation {
            name: "send_to_peer",
            code: -5,
        })?;
        // SAFETY: CString and payload live through the call, which copies the bytes.
        check_code("send_to_peer", unsafe {
            send(self.handle, peer.as_ptr(), payload.as_ptr(), length)
        })
    }
}

unsafe extern "C" fn on_packet_payload(sender: *const u8, data: *const u8, length: u32) {
    if sender.is_null() || data.is_null() {
        return;
    }
    // SAFETY: Moss passes a 32-byte sender key and length bytes, valid for this callback.
    let peer = hex::encode(unsafe { std::slice::from_raw_parts(sender, MOSS_PUBKEY_LEN) });
    // SAFETY: the native callback owns this live buffer until the callback returns.
    let payload = unsafe { std::slice::from_raw_parts(data, length as usize) }.to_vec();
    crate::inbox::deliver(MossReceivedMessage {
        channel: format!("{PACKET_INBOX_CHANNEL_PREFIX}{peer}"),
        payload,
    });
}
