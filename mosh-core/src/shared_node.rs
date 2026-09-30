//! The one moss node this process runs, and the refcount that keeps it up.
//!
//! Node identity is per process (the keystore is a process global), so N nodes
//! mean the SAME peer id announced from N ports. A remote peer keeps one
//! session per identity: it closes the rest the moment they arrive and declines
//! to dial the others at all, because it already holds that id. Measured across
//! three clients over three days: 33,715 sessions, 32,330 dead inside a second,
//! one identity on 27 different ports within an hour.
//!
//! Every conversation — DM, public channel, private group, org control — now
//! shares this node and separates itself by room (moss >= v0.8.19). A joined
//! room is byte-identical to a room the node was born in, so a consolidated
//! client still talks to every already-released one.
//!
//! This is the only node. Reaching a peer behind a NAT is moss's job — it
//! hole-punches or falls back to its own network relay — so nothing in this
//! process starts a second node for that.

use std::sync::{Arc, Mutex};

use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::moss_ffi::{clear_event_log, MossFfiError, MossFfiRuntime, MossNode, MossNodeConfig};

/// The room the shared node is born in. Carries no conversation traffic — each
/// conversation publishes in its own room — but a node must be born in some
/// room. Kept at the value DM nodes have used since v0.7.3 so the substrate a
/// released client sees does not move.
pub const SUBSTRATE_ROOM: &str = "mosh-dm/1";

#[derive(Debug)]
pub enum SharedNodeError {
    Moss(MossFfiError),
    /// The node was up a moment ago and is not now — only reachable if a
    /// release raced an acquire, which the mutex prevents. Kept explicit so the
    /// caller gets a message instead of a panic.
    Missing,
}

impl std::fmt::Display for SharedNodeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Moss(error) => write!(formatter, "{error}"),
            Self::Missing => write!(formatter, "shared moss node missing"),
        }
    }
}

impl std::error::Error for SharedNodeError {}

impl From<MossFfiError> for SharedNodeError {
    fn from(error: MossFfiError) -> Self {
        Self::Moss(error)
    }
}

struct SharedNodeState {
    node: Option<Arc<MossNode>>,
    refs: usize,
}

pub struct SharedMossNode {
    moss: Arc<MossFfiRuntime>,
    state: Mutex<SharedNodeState>,
}

impl SharedMossNode {
    pub fn new(moss: Arc<MossFfiRuntime>) -> Arc<Self> {
        Arc::new(Self {
            moss,
            state: Mutex::new(SharedNodeState {
                node: None,
                refs: 0,
            }),
        })
    }

    pub fn moss(&self) -> &Arc<MossFfiRuntime> {
        &self.moss
    }

    /// Bring the node up on first demand and take a reference to it; later
    /// callers bump the count and get the same handle.
    ///
    /// The node is born once, with the first caller's port — a later
    /// conversation only contributes its `static_peer`, which is dialled
    /// because the node is already listening. Start BEFORE bumping the count,
    /// or a transient init failure leaks a reference that can never be
    /// released.
    pub fn acquire(
        &self,
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<Arc<MossNode>, SharedNodeError> {
        let mut state = self.lock();
        match state.node.as_ref() {
            None => {
                let node = start_node(&self.moss, listen_port, static_peer)?;
                state.node = Some(Arc::new(node));
            }
            Some(node) => {
                if let Some(peer) = static_peer.as_deref() {
                    if let Err(error) = node.connect(peer) {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::CONNECT,
                            peer,
                            &format!("shared moss node could not dial: {error}"),
                        );
                    }
                }
            }
        }
        state.refs += 1;
        state.node.clone().ok_or(SharedNodeError::Missing)
    }

    /// Drop a reference. The last one stops moss (MossNode::drop → Moss_Stop).
    /// Callers must unsubscribe and leave their room first — on a shared node
    /// dropping the handle no longer ends a conversation's subscriptions.
    pub fn release(&self) {
        drop_ref(&mut self.lock());
    }

    /// The node if it is up, without taking a reference. For diagnostics.
    pub fn current(&self) -> Option<Arc<MossNode>> {
        self.lock().node.clone()
    }

    /// A poisoned lock means a panic while the node was being swapped. The
    /// state behind it is still structurally sound (an Option and a counter),
    /// so recovering beats propagating a panic into every conversation.
    fn lock(&self) -> std::sync::MutexGuard<'_, SharedNodeState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

/// Drop one reference, forgetting the node when the last holder lets go.
/// Split out so the refcount can be tested without a moss library to start a
/// node with.
fn drop_ref(state: &mut SharedNodeState) {
    state.refs = state.refs.saturating_sub(1);
    if state.refs == 0 {
        state.node = None;
    }
}

/// The field-log context for the stream-handler registration result, so the
/// line is greppable by call site rather than by peer.
const STREAM_HANDLER_CONTEXT: &str = "stream-handler";
const MAX_START_ATTEMPTS: usize = 3;

/// Starts on `listen_port`, reallocating after a bind collision. Port 0 is
/// never handed to Moss: default Moss Masq binds TCP first, then UDP on that
/// port, so an OS-picked TCP port can already be taken for UDP. A probed
/// [`dual_protocol_port`] closes that window instead of retrying into it.
/// A busy port used to keep the node down for the whole process: every
/// saved chat was dropped at startup and every new one failed with "could not
/// reach the network". Peers find the node through the trackers, so the port
/// number itself does not matter to them.
fn start_node(
    moss: &Arc<MossFfiRuntime>,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<MossNode, MossFfiError> {
    start_with_port_fallback(listen_port, |port| {
        start_node_on(moss, port, static_peer.clone())
    })
}

fn start_with_port_fallback<T>(
    listen_port: u16,
    mut start: impl FnMut(u16) -> Result<T, MossFfiError>,
) -> Result<T, MossFfiError> {
    let mut port = match listen_port {
        0 => dual_protocol_port(),
        port => port,
    };
    let mut result = start(port);
    for _ in 1..MAX_START_ATTEMPTS {
        let Err(error) = &result else {
            return result;
        };
        if !error.is_listen_failed() {
            return result;
        }
        dlog::write(
            LogLevel::Warn,
            kinds::CONNECT,
            &port.to_string(),
            &format!("listen port busy ({error}); starting on a free port"),
        );
        port = dual_protocol_port();
        result = start(port);
    }
    result
}

/// A port currently free for both TCP and UDP (their port spaces are
/// separate), or 0 to let Moss pick when no probe succeeds. Released before
/// Moss binds it, so a racer can still take it; the start retry covers that.
fn dual_protocol_port() -> u16 {
    const PROBE_ATTEMPTS: usize = 16;
    (0..PROBE_ATTEMPTS)
        .find_map(|_| {
            // Probe UDP first: on Windows, the OS ephemeral UDP allocator avoids
            // excluded ranges (e.g. WinNAT/Hyper-V), whereas probing TCP first can
            // return a port that is forbidden for UDP (WSAEACCES 10013).
            let udp = std::net::UdpSocket::bind(("0.0.0.0", 0)).ok()?;
            let port = udp.local_addr().ok()?.port();
            let tcp = std::net::TcpListener::bind(("0.0.0.0", port)).ok()?;
            drop(tcp);
            drop(udp);
            Some(port)
        })
        .unwrap_or(0)
}

fn start_node_on(
    moss: &Arc<MossFfiRuntime>,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<MossNode, MossFfiError> {
    let node = moss.init_default_node(
        SUBSTRATE_ROOM,
        &MossNodeConfig {
            listen_port,
            static_peer,
            bind_interface: None,
        },
    )?;
    node.set_message_callback()?;
    node.set_event_callback()?;
    // The attachment stream handler (spec #8) must be registered on the
    // RECEIVE side before any counterpart streams a chunk at us — "first
    // stream use" would only cover the sender. Idempotent per node (moss
    // replaces the entry on re-register), best-effort: a library without the
    // stream symbols simply keeps the room wire, so a missing symbol is a
    // note, never a start failure.
    if let Err(error) = node.register_stream_handler(crate::stream_transport::ATTACHMENT_STREAM_ID)
    {
        dlog::write(
            LogLevel::Warn,
            kinds::STREAM,
            STREAM_HANDLER_CONTEXT,
            &format!("attachment stream receive not available: {error}"),
        );
    }
    clear_event_log();
    if let Err(error) = node.start() {
        if let Some(reason) = node.last_error() {
            dlog::write(
                LogLevel::Warn,
                kinds::CONNECT,
                &listen_port.to_string(),
                &format!("moss start failed ({error}): {reason}"),
            );
        }
        return Err(error);
    }
    Ok(node)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn busy_port() -> MossFfiError {
        MossFfiError::Operation {
            name: "start",
            code: -13,
        }
    }

    #[test]
    fn an_auto_port_collision_allocates_another_port() {
        let mut outcomes = [Err(busy_port()), Ok(42)].into_iter();
        assert_eq!(
            start_with_port_fallback(0, |_| outcomes.next().unwrap()).unwrap(),
            42
        );
    }

    #[test]
    fn a_busy_explicit_port_can_survive_an_auto_port_collision_too() {
        let mut outcomes = [Err(busy_port()), Err(busy_port()), Ok(42)].into_iter();
        let mut ports = Vec::new();
        let node = start_with_port_fallback(12345, |port| {
            ports.push(port);
            outcomes.next().unwrap()
        })
        .unwrap();
        assert_eq!(node, 42);
        assert_eq!(ports[0], 12345);
        assert!(ports[1..].iter().all(|port| *port != 12345));
    }

    /// Moss binds TCP and then UDP on the same number, so the fallback port
    /// must be free for both.
    #[test]
    fn the_fallback_port_binds_for_tcp_and_udp() {
        let port = dual_protocol_port();
        assert_ne!(port, 0);
        let _tcp = std::net::TcpListener::bind(("0.0.0.0", port)).expect("TCP free");
        std::net::UdpSocket::bind(("0.0.0.0", port)).expect("UDP free");
    }

    #[test]
    fn non_bind_failures_are_returned_without_reallocation() {
        let mut outcomes = [Err::<(), _>(MossFfiError::Operation {
            name: "start",
            code: -8,
        })]
        .into_iter();
        let error = start_with_port_fallback(0, |_| outcomes.next().unwrap()).unwrap_err();
        assert!(matches!(error, MossFfiError::Operation { code: -8, .. }));
    }

    #[test]
    fn repeated_bind_failures_stop_after_three_attempts() {
        let mut attempts = 0;
        let error = start_with_port_fallback(0, |_| {
            attempts += 1;
            Err::<(), _>(busy_port())
        })
        .unwrap_err();
        assert!(error.is_listen_failed());
        assert_eq!(attempts, 3);
    }

    /// Refcounting is the whole contract: the node stays up until the last
    /// holder lets go, and a stray extra release must not underflow the count
    /// into "never stops again".
    #[test]
    fn node_survives_every_release_but_the_last() {
        let mut state = SharedNodeState {
            node: None,
            refs: 2,
        };

        drop_ref(&mut state);
        assert_eq!(state.refs, 1, "one holder left, node must stay up");

        drop_ref(&mut state);
        assert_eq!(state.refs, 0, "last release stops the node");

        drop_ref(&mut state);
        assert_eq!(state.refs, 0, "releasing past zero saturates");
    }

    /// Field case (0.9.5, macOS): a dead previous process still held the
    /// UDP port, moss refused to start (-13) and every chat vanished. A busy
    /// port must not keep the node down.
    #[test]
    fn node_starts_when_the_listen_port_is_taken() {
        let squatter = std::net::UdpSocket::bind("0.0.0.0:0").expect("free UDP port");
        let busy_port = squatter.local_addr().expect("bound address").port();
        let moss = Arc::new(MossFfiRuntime::load_default().expect("moss library"));
        let shared = SharedMossNode::new(moss);

        shared
            .acquire(busy_port, None)
            .expect("node must start on another port");
        shared.release();
    }
}
