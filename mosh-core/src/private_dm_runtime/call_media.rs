//! Voice-call media, apart from the DM runtime.
//!
//! The audio loop sends and drains a frame every 20 ms. Through the runtime
//! each of those calls took the runtime's one lock and ran a full drain and
//! tick (mesh report, hellos, outbox, resends, persistence), so a busy tick
//! or a slow chunk send turned into gaps in the voice. The hub holds only
//! what media needs — which calls are live, their room, which direction is
//! ours — and talks to the transport directly. The runtime stays the owner
//! of the call state machine and pushes the live set here after every change
//! (`PrivateDmRuntime::sync_call_media`).

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, MutexGuard};

use super::transport::{DmTransport, PublishError};
use super::wire::{channel_call_id, voice_call_channel};

/// One second of 20 ms frames. A call nobody drains for longer than that has
/// no use for older audio, and the queue must not grow without bound.
const INBOUND_CAP: usize = 50;

/// A live call as the hub needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct LiveCall {
    pub call_id: String,
    pub room: String,
    /// The direction bit our own frames carry in their sequence header.
    pub own_direction_bit: u64,
}

struct Route {
    room: String,
    own_direction_bit: u64,
    inbound: VecDeque<Vec<u8>>,
}

pub struct CallMedia {
    transport: Arc<dyn DmTransport>,
    calls: Mutex<HashMap<String, Route>>,
}

impl CallMedia {
    pub fn new(transport: Arc<dyn DmTransport>) -> Arc<Self> {
        Arc::new(Self {
            transport,
            calls: Mutex::new(HashMap::new()),
        })
    }

    /// Replace the set of live calls. A call that stays keeps its queued
    /// frames; a call that ended loses them.
    pub(crate) fn sync(&self, live: Vec<LiveCall>) {
        let mut calls = self.calls();
        calls.retain(|call_id, _| live.iter().any(|call| &call.call_id == call_id));
        for call in live {
            calls.entry(call.call_id).or_insert_with(|| Route {
                room: call.room,
                own_direction_bit: call.own_direction_bit,
                inbound: VecDeque::new(),
            });
        }
    }

    /// Publish one sealed frame for a live call. A frame for a call that is
    /// not live is dropped, and "nobody to take it" is not an error: the next
    /// frame is 20 ms away.
    pub fn send(&self, call_id: &str, frame: &[u8]) -> Result<(), String> {
        let Some(room) = self.calls().get(call_id).map(|route| route.room.clone()) else {
            return Ok(());
        };
        match self
            .transport
            .publish(&room, &voice_call_channel(call_id), frame)
        {
            Ok(()) | Err(PublishError::NoPeers(_)) => Ok(()),
            Err(error) => Err(error.to_string()),
        }
    }

    /// The counterpart's frames for `call_id` that arrived since the last
    /// drain, oldest first.
    pub fn drain(&self, call_id: &str) -> Vec<Vec<u8>> {
        let arrived = self.transport.drain_media();
        let mut calls = self.calls();
        for message in arrived {
            let Some(route) = channel_call_id(&message.channel).and_then(|id| calls.get_mut(id))
            else {
                continue;
            };
            if frame_direction_bit(&message.payload) == Some(route.own_direction_bit) {
                continue; // our own frame, delivered back to us
            }
            if route.inbound.len() >= INBOUND_CAP {
                route.inbound.pop_front();
            }
            route.inbound.push_back(message.payload);
        }
        calls
            .get_mut(call_id)
            .map(|route| route.inbound.drain(..).collect())
            .unwrap_or_default()
    }

    fn calls(&self) -> MutexGuard<'_, HashMap<String, Route>> {
        // Plain data: a panic elsewhere must not silence every later call.
        self.calls
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// The direction bit in a frame's big-endian sequence header.
fn frame_direction_bit(bytes: &[u8]) -> Option<u64> {
    let header: [u8; 8] = bytes.get(..8)?.try_into().ok()?;
    Some(u64::from_be_bytes(header) & (1 << 63))
}
