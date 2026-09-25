//! An in-process network for tests: endpoints by peer id, one inbox each, and
//! a link per direction that says how the far end is reachable and which
//! frames get lost on the way.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use super::{DmTransport, PeerTransport, PublishError};
use crate::conversation::mesh::{MeshInfo, PeerDetail};
use crate::moss_ffi::MossReceivedMessage;
use crate::stream_transport::{passthrough_or_deframe, stream_inbox_channel};

type DropRule = Arc<dyn Fn(&str, &[u8]) -> bool + Send + Sync>;

#[derive(Default)]
struct Endpoint {
    inbox: Vec<MossReceivedMessage>,
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
}

#[derive(Clone)]
struct Link {
    reach: PeerTransport,
    drop_if: Option<DropRule>,
}

#[derive(Default)]
struct NetState {
    endpoints: HashMap<String, Endpoint>,
    links: HashMap<(String, String), Link>,
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
        })
    }

    /// Make `from` see `to` as reachable this way, in that direction only.
    pub fn link(&self, from: &str, to: &str, reach: PeerTransport) {
        let mut state = self.lock();
        let link = state
            .links
            .entry((from.to_string(), to.to_string()))
            .or_insert(Link {
                reach: PeerTransport::None,
                drop_if: None,
            });
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
            .or_insert(Link {
                reach: PeerTransport::None,
                drop_if: None,
            });
        link.drop_if = Some(Arc::new(rule));
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
}

impl MemoryTransport {
    fn reachable_peers(&self, state: &NetState) -> Vec<PeerDetail> {
        state
            .links
            .iter()
            .filter(|((from, _), link)| *from == self.peer_id && link.reach != PeerTransport::None)
            .map(|((_, to), link)| PeerDetail {
                id: to.clone(),
                addr: String::new(),
                relayed: link.reach == PeerTransport::Relayed,
            })
            .collect()
    }
}

impl DmTransport for MemoryTransport {
    fn open_room(
        &self,
        _room: &str,
        _channels: &[String],
        _listen_port: u16,
        _static_peer: Option<String>,
    ) -> Result<(), String> {
        Ok(())
    }

    fn close_room(&self, _room: &str, _channels: &[String], _label: &str) {}

    fn subscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        let refused = self
            .net
            .lock()
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.refuse_subscribes);
        if refused {
            Err("subscribe refused".to_string())
        } else {
            Ok(())
        }
    }

    fn unsubscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        Ok(())
    }

    fn publish(&self, _room: &str, channel: &str, payload: &[u8]) -> Result<(), PublishError> {
        let mut state = self.net.lock();
        let refused = state
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.refuse_publishes);
        let targets: Vec<(String, Option<DropRule>)> = state
            .links
            .iter()
            .filter(|((from, _), link)| *from == self.peer_id && link.reach != PeerTransport::None)
            .map(|((_, to), link)| (to.clone(), link.drop_if.clone()))
            .collect();
        if refused || targets.is_empty() {
            return Err(PublishError::NoPeers("no peers reachable".to_string()));
        }
        let fail = state
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.fail_publishes);
        if fail {
            return Err(PublishError::Other("publish failed".to_string()));
        }
        for (to, drop_if) in targets {
            if drop_if.is_some_and(|rule| rule(channel, payload)) {
                continue;
            }
            if let Some(endpoint) = state.endpoints.get_mut(&to) {
                endpoint.inbox.push(MossReceivedMessage {
                    channel: channel.to_string(),
                    payload: payload.to_vec(),
                });
            }
        }
        Ok(())
    }

    fn connect_peer(&self, peer_moss_id: &str) -> Result<(), String> {
        let mut state = self.net.lock();
        if let Some(endpoint) = state.endpoints.get_mut(&self.peer_id) {
            endpoint.connect_requests.push(peer_moss_id.to_string());
        }
        Ok(())
    }

    fn reach(&self, peer_moss_id: &str) -> PeerTransport {
        self.net
            .lock()
            .links
            .get(&(self.peer_id.clone(), peer_moss_id.to_string()))
            .map_or(PeerTransport::None, |link| link.reach)
    }

    fn local_peer_id(&self) -> Option<String> {
        Some(self.peer_id.clone())
    }

    fn mesh_info(&self) -> Option<MeshInfo> {
        let state = self.net.lock();
        let peer_details = self.reachable_peers(&state);
        Some(MeshInfo {
            mesh_id: "memory".to_string(),
            peer_count: peer_details.len() as i32,
            peer_details,
            ..Default::default()
        })
    }

    /// A stream frame lands on the far end under the reserved stream
    /// channel, framed, exactly the way the moss stream callback files it.
    fn send_to_peer_stream(&self, peer_id: &str, payload: &[u8]) -> Result<(), String> {
        let mut state = self.net.lock();
        let reachable = state
            .links
            .get(&(self.peer_id.clone(), peer_id.to_string()))
            .is_some_and(|link| link.reach != PeerTransport::None);
        let Some(endpoint) = state.endpoints.get_mut(&self.peer_id) else {
            return Err("no such endpoint".to_string());
        };
        endpoint.stream_attempts += 1;
        if endpoint.fail_streams || !reachable {
            return Err("stream refused".to_string());
        }
        if let Some(target) = state.endpoints.get_mut(peer_id) {
            target.inbox.push(MossReceivedMessage {
                channel: stream_inbox_channel(&self.peer_id),
                payload: payload.to_vec(),
            });
        }
        Ok(())
    }

    fn drain(&self) -> Vec<MossReceivedMessage> {
        let mut state = self.net.lock();
        state
            .endpoints
            .get_mut(&self.peer_id)
            .map(|endpoint| std::mem::take(&mut endpoint.inbox))
            .unwrap_or_default()
            .into_iter()
            .map(passthrough_or_deframe)
            .collect()
    }
}
