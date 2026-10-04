use std::collections::HashSet;
use std::sync::{Arc, OnceLock};

use super::types::{DeviceLinkError, DeviceLinkErrorKind, Result};
use crate::inbox::{self, Inbox};
use crate::moss_ffi::{MossNode, MossReceivedMessage};
use crate::shared_node::SharedMossNode;

pub const LINK_CHANNEL: &str = "mosh-device-link";
pub(crate) const LINK_STREAM_ID: u32 = 3;
static INBOX: OnceLock<Inbox> = OnceLock::new();

pub(crate) struct LinkTransport {
    shared: Arc<SharedMossNode>,
    node: Arc<MossNode>,
    requested: HashSet<String>,
    #[cfg(test)]
    pub(crate) sent_packets: Vec<Vec<u8>>,
}

impl LinkTransport {
    pub fn new(shared: Arc<SharedMossNode>) -> Result<Self> {
        INBOX.get_or_init(|| inbox::register(|channel| channel == LINK_CHANNEL));
        let node = shared.acquire(0, None).map_err(|_| unavailable())?;
        if node.register_stream_handler(LINK_STREAM_ID).is_err() {
            shared.release();
            return Err(unavailable());
        }
        Ok(Self {
            shared,
            node,
            requested: HashSet::new(),
            #[cfg(test)]
            sent_packets: Vec::new(),
        })
    }

    pub fn peer_id(&self) -> Result<String> {
        self.node.public_key_hex().ok_or_else(unavailable)
    }

    pub fn send(&mut self, peer: &str, packet: &[u8]) -> Result<()> {
        #[cfg(test)]
        self.sent_packets.push(packet.to_vec());
        if !self.requested.contains(peer) {
            // Moss retains this target and retries its handshake itself.
            self.node
                .connect_to_peer(peer)
                .map_err(|_| disconnected())?;
            self.requested.insert(peer.to_owned());
        }
        // SendStream starts its reader itself. OpenStream would perform a
        // blocking overlay lookup while the runtime holds the service lock;
        // the retained connect request and protocol retries own discovery.
        self.node
            .send_stream(peer, LINK_STREAM_ID, packet)
            .map_err(|_| disconnected())
    }

    pub fn drain(&self) -> Vec<MossReceivedMessage> {
        // OnStream starts readers for peers connected since registration.
        // Moss's periodic reader refresh otherwise waits up to 30 seconds.
        let _ = self.node.register_stream_handler(LINK_STREAM_ID);
        INBOX.get().map(Inbox::drain).unwrap_or_default()
    }
}

fn unavailable() -> DeviceLinkError {
    DeviceLinkError::new(DeviceLinkErrorKind::Unavailable)
}
fn disconnected() -> DeviceLinkError {
    DeviceLinkError::new(DeviceLinkErrorKind::ConnectionLost)
}

impl Drop for LinkTransport {
    fn drop(&mut self) {
        self.shared.release();
    }
}
