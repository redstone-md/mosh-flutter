//! The one door a DM's frames go through.
//!
//! A session never touches moss. It hands frames to a [`DmTransport`], asks it
//! to reach a peer, and asks how that peer is reachable right now. The
//! production transport is the shared moss node; a test wires two runtimes
//! together through [`MemoryNet`] and decides which frames get through.
//!
//! `publish` answers "the transport took the frame", never "the peer has it".
//! A second transport behind this trait (the paid mailbox) will accept a frame
//! for a peer that is offline, so nothing here may assume a live counterpart.

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::wire::{channel_call_id, channel_session_id};
use crate::conversation::mesh::{self, MeshInfo};
use crate::conversation::runtime;
use crate::inbox;
use crate::moss_ffi::MossReceivedMessage;
use crate::shared_node::SharedMossNode;
use flutter_rust_bridge::frb;

/// How the counterpart is reachable through the transport right now.
#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PeerTransport {
    Direct,
    /// Through moss's own network relay. Still end to end: the relay sees only
    /// ciphertext.
    Relayed,
    /// Not reachable, or the peer is not known yet.
    None,
}

/// Why the transport did not take a frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PublishError {
    /// Nobody to hand the frame to. The normal state before the mesh forms; a
    /// frame that repeats on its own cadence ignores it, a queued message
    /// waits.
    NoPeers(String),
    Other(String),
}

impl std::fmt::Display for PublishError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoPeers(message) | Self::Other(message) => write!(formatter, "{message}"),
        }
    }
}

pub trait DmTransport: Send + Sync {
    /// Put a session's room on the transport and listen on its channels.
    fn open_room(
        &self,
        room: &str,
        channels: &[String],
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<(), String>;

    /// The inverse of [`DmTransport::open_room`]. `label` names the session
    /// in a log line.
    fn close_room(&self, room: &str, channels: &[String], label: &str);

    fn subscribe(&self, room: &str, channel: &str) -> Result<(), String>;

    fn unsubscribe(&self, room: &str, channel: &str) -> Result<(), String>;

    /// Hand one frame to the transport. `Ok` means the transport accepted it,
    /// not that anyone received it.
    fn publish(&self, room: &str, channel: &str, payload: &[u8]) -> Result<(), PublishError>;

    /// Ask the transport to reach this peer. Non-blocking: the transport keeps
    /// trying on its own once asked.
    fn connect_peer(&self, peer_moss_id: &str) -> Result<(), String>;

    fn reach(&self, peer_moss_id: &str) -> PeerTransport;

    /// This installation's own moss peer id, once the node is up.
    fn local_peer_id(&self) -> Option<String>;

    fn mesh_info(&self) -> Option<MeshInfo>;

    /// The stream fast path (spec #8): one framed blob frame to this peer
    /// over the moss attachment stream. Default: no streams — a transport
    /// that cannot stream (the memory test net, any future non-moss
    /// transport) answers refused and the carrier falls back to the room
    /// wire, which is exactly the mixed-version behavior.
    fn send_to_peer_stream(&self, peer_id: &str, payload: &[u8]) -> Result<(), String> {
        let _ = (peer_id, payload);
        Err(STREAMS_UNSUPPORTED.to_string())
    }

    /// Every frame that arrived since the last call.
    fn drain(&self) -> Vec<MossReceivedMessage>;
}

const STREAMS_UNSUPPORTED: &str = "transport has no stream fast path";

/// How `peer` is reachable according to one mesh report. The shared node
/// connects network-wide, so the counts say nothing about one counterpart;
/// only a row in `peer_details` does.
pub fn reach_of(peer_moss_id: &str, info: &MeshInfo) -> PeerTransport {
    match info
        .peer_details
        .iter()
        .find(|peer| peer.id == peer_moss_id)
    {
        Some(peer) if peer.relayed => PeerTransport::Relayed,
        Some(_) => PeerTransport::Direct,
        None => PeerTransport::None,
    }
}

pub(crate) fn is_private_dm_inbound(channel: &str) -> bool {
    channel_session_id(channel).is_some()
        || channel_call_id(channel).is_some()
        // Stream-delivered frames (spec #8): the carrier deframes them in
        // drain, so the runtime sees the ordinary blob/data/control channel
        // inside — but the queue has to claim the frame when it lands.
        || crate::stream_transport::is_stream_inbound(channel)
}

/// The DM's own inbound queue, claimed once for the process. Two DM runtimes
/// in one process (the two peers a moss loopback test runs) share it.
fn dm_inbox() -> &'static inbox::Inbox {
    static INBOX: std::sync::OnceLock<inbox::Inbox> = std::sync::OnceLock::new();
    INBOX.get_or_init(|| inbox::register(is_private_dm_inbound))
}

const NODE_DOWN: &str = "moss node is not running";

/// The production transport: the one moss node this process runs. It never
/// keeps the node handle. The holder refcounts it per open room, and a handle
/// kept here would outlive the last room and keep a second node from being
/// the only one.
pub struct MossDmTransport {
    shared_node: Arc<SharedMossNode>,
}

impl MossDmTransport {
    pub fn new(shared_node: Arc<SharedMossNode>) -> Arc<Self> {
        // Claim the DM channels before any node can start: a frame that
        // lands before its owner is registered goes to the unclaimed tail,
        // and no drain will ever see it.
        dm_inbox();
        Arc::new(Self { shared_node })
    }

    fn node(&self) -> Result<Arc<crate::moss_ffi::MossNode>, String> {
        self.shared_node
            .current()
            .ok_or_else(|| NODE_DOWN.to_string())
    }
}

impl DmTransport for MossDmTransport {
    fn open_room(
        &self,
        room: &str,
        channels: &[String],
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<(), String> {
        runtime::open_room(&self.shared_node, room, channels, listen_port, static_peer).map(|_| ())
    }

    fn close_room(&self, room: &str, channels: &[String], label: &str) {
        match self.node() {
            Ok(node) => runtime::close_room(&self.shared_node, &node, room, channels, label),
            Err(error) => eprintln!("{label} could not close its room: {error}"),
        }
    }

    fn subscribe(&self, room: &str, channel: &str) -> Result<(), String> {
        self.node()?
            .subscribe_room(room, channel)
            .map_err(|error| error.to_string())
    }

    fn unsubscribe(&self, room: &str, channel: &str) -> Result<(), String> {
        self.node()?
            .unsubscribe_room(room, channel)
            .map_err(|error| error.to_string())
    }

    fn publish(&self, room: &str, channel: &str, payload: &[u8]) -> Result<(), PublishError> {
        let node = self.node().map_err(PublishError::Other)?;
        node.publish_room(room, channel, payload)
            .map_err(|error| match error.is_no_peers() {
                true => PublishError::NoPeers(error.to_string()),
                false => PublishError::Other(error.to_string()),
            })
    }

    fn connect_peer(&self, peer_moss_id: &str) -> Result<(), String> {
        self.node()?
            .connect_to_peer(peer_moss_id)
            .map_err(|error| error.to_string())
    }

    fn reach(&self, peer_moss_id: &str) -> PeerTransport {
        self.mesh_info()
            .map_or(PeerTransport::None, |info| reach_of(peer_moss_id, &info))
    }

    fn local_peer_id(&self) -> Option<String> {
        self.node().ok()?.public_key_hex()
    }

    fn mesh_info(&self) -> Option<MeshInfo> {
        let node = self.node().ok()?;
        mesh::mesh_info(&node)
    }

    fn send_to_peer_stream(&self, peer_id: &str, payload: &[u8]) -> Result<(), String> {
        let node = self.node()?;
        // OpenStream on a relayed peer is an immediate OK in moss — the wrap
        // happens inside Moss_SendStream — so this never stalls waiting on a
        // dial for the relayed case. A missing symbol surfaces as
        // Err(Symbol), which the carrier treats like any other refusal.
        node.open_stream(peer_id, crate::stream_transport::ATTACHMENT_STREAM_ID)
            .map_err(|error| error.to_string())?;
        node.send_stream(peer_id, crate::stream_transport::ATTACHMENT_STREAM_ID, payload)
            .map_err(|error| error.to_string())
    }

    fn drain(&self) -> Vec<MossReceivedMessage> {
        dm_inbox()
            .drain()
            .into_iter()
            .map(|message| {
                // Stream-delivered frames arrive under the reserved
                // moss-stream/<peer> channel with the real blob channel
                // inside; peel the framing here so the runtime's route_frame
                // sees the ordinary channel naming. Room frames pass as-is —
                // `ingest` is identity for them (no reserved prefix, no
                // re-file).
                crate::stream_transport::passthrough_or_deframe(message)
            })
            .collect()
    }
}

#[cfg(test)]
pub mod memory;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conversation::mesh::PeerDetail;

    fn peer(id: &str, relayed: bool) -> PeerDetail {
        PeerDetail {
            id: id.to_string(),
            addr: "10.0.0.1:4001".to_string(),
            relayed,
        }
    }

    // The shared node connects to unrelated world peers, so a crowded mesh
    // says nothing about one counterpart: only its own row does.
    #[test]
    fn reach_matches_the_counterpart_row_not_the_crowd() {
        let counterpart = "aa".repeat(32);
        let stranger = "bb".repeat(32);

        let crowd = MeshInfo {
            peer_count: 50,
            direct_peer_count: 40,
            peer_details: vec![peer(&stranger, false)],
            ..Default::default()
        };
        assert_eq!(reach_of(&counterpart, &crowd), PeerTransport::None);

        let relayed = MeshInfo {
            peer_details: vec![peer(&stranger, false), peer(&counterpart, true)],
            ..Default::default()
        };
        assert_eq!(reach_of(&counterpart, &relayed), PeerTransport::Relayed);

        let direct = MeshInfo {
            peer_details: vec![peer(&counterpart, false)],
            ..Default::default()
        };
        assert_eq!(reach_of(&counterpart, &direct), PeerTransport::Direct);
    }

    #[test]
    fn memory_net_delivers_only_over_reachable_links_and_honors_drops() {
        use memory::MemoryNet;
        let net = MemoryNet::new();
        let a = net.endpoint("a");
        let b = net.endpoint("b");

        // No link yet: nobody to publish to.
        assert!(matches!(
            a.publish("room", "chan", b"x"),
            Err(PublishError::NoPeers(_))
        ));
        assert_eq!(a.reach("b"), PeerTransport::None);

        net.link("a", "b", PeerTransport::Relayed);
        assert_eq!(a.reach("b"), PeerTransport::Relayed);
        assert_eq!(b.reach("a"), PeerTransport::None, "links are one-way");
        a.publish("room", "chan", b"one")
            .expect("linked publish is accepted");
        assert_eq!(b.drain().len(), 1);
        assert!(
            a.drain().is_empty(),
            "a frame never comes back to its sender"
        );

        net.drop_frames("a", "b", |_, payload| payload == b"lost");
        a.publish("room", "chan", b"lost")
            .expect("a dropped frame is still accepted");
        a.publish("room", "chan", b"kept").expect("publish");
        let kept = b.drain();
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].payload, b"kept");

        a.connect_peer("b").expect("connect is recorded");
        assert_eq!(net.connect_requests("a"), vec!["b".to_string()]);
    }
}
