//! An in-process network for tests: endpoints by peer id, one inbox each, and
//! a link per direction that says how the far end is reachable and which
//! frames get lost on the way.

mod authentication;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use super::super::admission_authentication::sign_key_package;
use super::{is_call_media_inbound, DmTransport, PeerTransport, PublishError};
use crate::conversation::mesh::{MeshInfo, PeerDetail};
use crate::moss_ffi::MossReceivedMessage;
use crate::stream_transport::{passthrough_or_deframe, stream_inbox_channel};

type DropRule = Arc<dyn Fn(&str, &[u8]) -> bool + Send + Sync>;

#[derive(Default)]
struct Endpoint {
    inbox: Vec<MossReceivedMessage>,
    /// Voice-call media, queued apart the way the moss inbox claims it.
    media_inbox: Vec<MossReceivedMessage>,
    connect_requests: Vec<String>,
    /// The transport turns every publish away, the way moss answers a
    /// node with nobody to hand the frame to.
    refuse_publishes: bool,
    /// The transport turns the next publish into a hard failure (the way
    /// moss answers a real transport fault, not a soft no-peers refusal).
    fail_publishes: bool,
    /// `subscribe` answers an error, the way moss would when the room or
    /// the node behind it is gone.
    refuse_subscribes: bool,
    /// Every stream send this endpoint tried, delivered or not.
    stream_attempts: usize,
    /// The stream fast path refuses, the way a moss stream refuses a peer it
    /// cannot open.
    fail_streams: bool,
    /// The mesh report fails, the way moss's does while the node restarts:
    /// no report, and so no path to anyone.
    fail_mesh_reports: bool,
}

#[derive(Clone)]
struct Link {
    reach: PeerTransport,
    drop_if: Option<DropRule>,
    /// Moss lists the far end in its peer table. A room frame can cross a
    /// link moss does not list: gossip reaches the peer through others.
    listed: bool,
}

impl Link {
    fn new() -> Self {
        Self {
            reach: PeerTransport::None,
            drop_if: None,
            listed: true,
        }
    }

    /// How `reach` and the mesh report see this link.
    fn visible_reach(&self) -> PeerTransport {
        if self.listed {
            self.reach
        } else {
            PeerTransport::None
        }
    }
}

#[derive(Default)]
struct NetState {
    endpoints: HashMap<String, Endpoint>,
    links: HashMap<(String, String), Link>,
}

impl NetState {
    fn reports_fail(&self, peer_id: &str) -> bool {
        self.endpoints
            .get(peer_id)
            .is_some_and(|endpoint| endpoint.fail_mesh_reports)
    }
}

#[derive(Default)]
pub struct MemoryNet {
    state: Mutex<NetState>,
}

impl MemoryNet {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// An endpoint of this network, registered on first use.
    pub fn endpoint(self: &Arc<Self>, peer_id: &str) -> Arc<MemoryTransport> {
        self.lock()
            .endpoints
            .entry(peer_id.to_string())
            .or_default();
        Arc::new(MemoryTransport {
            net: Arc::clone(self),
            peer_id: peer_id.to_string(),
            identity: None,
        })
    }

    /// Make `from` see `to` as reachable this way, in that direction only.
    pub fn link(&self, from: &str, to: &str, reach: PeerTransport) {
        let mut state = self.lock();
        let link = state
            .links
            .entry((from.to_string(), to.to_string()))
            .or_insert_with(Link::new);
        link.reach = reach;
    }

    /// Both directions at once.
    pub fn link_both(&self, a: &str, b: &str, reach: PeerTransport) {
        self.link(a, b, reach);
        self.link(b, a, reach);
    }

    /// Lose every frame from `from` to `to` that the rule accepts, given
    /// the channel and the payload.
    pub fn drop_frames(
        &self,
        from: &str,
        to: &str,
        rule: impl Fn(&str, &[u8]) -> bool + Send + Sync + 'static,
    ) {
        let mut state = self.lock();
        let link = state
            .links
            .entry((from.to_string(), to.to_string()))
            .or_insert_with(Link::new);
        link.drop_if = Some(Arc::new(rule));
    }

    /// Frames from `from` still reach `to`, but `from`'s moss has no peer
    /// table row for `to` — the field case where gossip carries a chat that
    /// moss reports no path for.
    pub fn unlist(&self, from: &str, to: &str) {
        if let Some(link) = self
            .lock()
            .links
            .get_mut(&(from.to_string(), to.to_string()))
        {
            link.listed = false;
        }
    }

    /// Make every publish from `from` come back refused, or stop doing so.
    pub fn refuse_publishes(&self, from: &str, refuse: bool) {
        if let Some(endpoint) = self.lock().endpoints.get_mut(from) {
            endpoint.refuse_publishes = refuse;
        }
    }

    /// Make every publish from `from` fail as a transport fault (never the
    /// soft no-peers refusal), or stop doing so.
    pub fn fail_publishes(&self, from: &str, fail: bool) {
        if let Some(endpoint) = self.lock().endpoints.get_mut(from) {
            endpoint.fail_publishes = fail;
        }
    }

    /// Make `from`'s subscribes fail, or stop doing so.
    pub fn refuse_subscribes(&self, from: &str, refuse: bool) {
        if let Some(endpoint) = self.lock().endpoints.get_mut(from) {
            endpoint.refuse_subscribes = refuse;
        }
    }

    /// Make every stream send from `from` fail, or stop doing so.
    pub fn fail_streams(&self, from: &str, fail: bool) {
        if let Some(endpoint) = self.lock().endpoints.get_mut(from) {
            endpoint.fail_streams = fail;
        }
    }

    /// Make `from`'s mesh reports fail, or stop doing so.
    pub fn fail_mesh_reports(&self, from: &str, fail: bool) {
        if let Some(endpoint) = self.lock().endpoints.get_mut(from) {
            endpoint.fail_mesh_reports = fail;
        }
    }

    /// How many stream sends `from` tried.
    pub fn stream_attempts(&self, from: &str) -> usize {
        self.lock()
            .endpoints
            .get(from)
            .map_or(0, |endpoint| endpoint.stream_attempts)
    }

    /// The peers `from` asked the transport to reach, in order.
    pub fn connect_requests(&self, from: &str) -> Vec<String> {
        self.lock()
            .endpoints
            .get(from)
            .map(|endpoint| endpoint.connect_requests.clone())
            .unwrap_or_default()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, NetState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

pub struct MemoryTransport {
    net: Arc<MemoryNet>,
    peer_id: String,
    identity: Option<ed25519_dalek::SigningKey>,
}

impl MemoryTransport {
    fn reachable_peers(&self, state: &NetState) -> Vec<PeerDetail> {
        state
            .links
            .iter()
            .filter(|((from, _), link)| {
                *from == self.peer_id && link.visible_reach() != PeerTransport::None
            })
            .map(|((_, to), link)| PeerDetail {
                id: to.clone(),
                addr: String::new(),
                relayed: link.reach == PeerTransport::Relayed,
            })
            .collect()
    }
}

mod transport;
