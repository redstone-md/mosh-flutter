//! Optional stream capabilities. Missing symbols preserve room-wire fallback.
use super::*;

impl MossNode {
    pub fn open_stream(&self, peer_id: &str, stream_id: u32) -> Result<(), MossFfiError> {
        let peer = c_string(peer_id)?;
        let open = self
            .runtime
            .open_stream
            .ok_or_else(|| MossFfiError::Symbol(STREAM_SYMBOL.to_string()))?;
        check_code("open_stream", unsafe {
            open(self.handle, peer.as_ptr(), stream_id)
        })
    }

    pub fn send_stream(
        &self,
        peer_id: &str,
        stream_id: u32,
        payload: &[u8],
    ) -> Result<(), MossFfiError> {
        let peer = c_string(peer_id)?;
        let send = self
            .runtime
            .send_stream
            .ok_or_else(|| MossFfiError::Symbol(STREAM_SYMBOL.to_string()))?;
        check_code("send_stream", unsafe {
            send(
                self.handle,
                peer.as_ptr(),
                stream_id,
                payload.as_ptr(),
                payload.len() as u32,
            )
        })
    }

    pub fn register_stream_handler(&self, stream_id: u32) -> Result<(), MossFfiError> {
        let on_stream = self
            .runtime
            .on_stream
            .ok_or_else(|| MossFfiError::Symbol(STREAM_SYMBOL.to_string()))?;
        check_code("on_stream", unsafe {
            on_stream(self.handle, stream_id, Some(on_stream_payload))
        })
    }
}

const STREAM_SYMBOL: &str = "Moss_OpenStream/Moss_SendStream/Moss_OnStream";
