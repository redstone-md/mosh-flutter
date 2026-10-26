//! One bounded owner for recipient-directed history, separate from call packets.
pub(crate) const PREFIX: &[u8] = b"mosh-history-v1\0";

pub(crate) struct Packet {
    /// Callback-provided claim; only the kind's signature/membership checks authenticate it.
    pub claimed_peer: String,
    pub payload: Vec<u8>,
}

mod bounded;
mod generation;
mod worker;
use bounded::Bounded;
pub(crate) use generation::{active_sends, DispatchGeneration, DispatchPermit};
use std::sync::Mutex;
pub(crate) use worker::enqueue;

static INBOUND: Mutex<Bounded<Packet>> = Mutex::new(Bounded::new());

/// True means this prefix is owned here, including frames dropped by its limits.
pub(crate) fn offer(from_peer: &str, payload: &[u8]) -> bool {
    let Some(body) = payload.strip_prefix(PREFIX) else {
        return false;
    };
    if payload.len() <= crate::conversation::MAX_PUBLISH_BYTES && from_peer.len() <= 128 {
        let mut queue = INBOUND.lock().unwrap_or_else(|p| p.into_inner());
        let bytes = payload.len() + from_peer.len();
        if queue.has_room(bytes) {
            queue.push(
                Packet {
                    claimed_peer: from_peer.into(),
                    payload: body.into(),
                },
                bytes,
            );
        }
    }
    true
}

/// The group history owner is the only reader; callback claims remain untrusted.
pub(crate) fn drain() -> Vec<Packet> {
    INBOUND.lock().unwrap_or_else(|p| p.into_inner()).drain()
}

/// Explicit execution shutdown/reset only; timed UI locks keep background work alive.
pub(crate) fn cancel_pending() {
    generation::cancel();
    worker::cancel_queued();
    INBOUND.lock().unwrap_or_else(|p| p.into_inner()).drain();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::moss_ffi::MOSS_TEST_LOCK;

    #[test]
    fn the_single_history_inbox_claims_its_prefix_and_bounds_frames_and_carrier_bytes() {
        let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        drain();
        assert!(!offer("claimed", b"ordinary-call-packet"));
        let payload = [PREFIX, b"signed-body"].concat();
        assert!(offer("claimed", &payload));
        let packets = drain();
        assert_eq!(packets.len(), 1);
        assert_eq!(packets[0].claimed_peer, "claimed");
        assert_eq!(packets[0].payload, b"signed-body");
        for _ in 0..40 {
            assert!(offer("claimed", &payload));
        }
        assert_eq!(drain().len(), 32);
        let large = [PREFIX, &vec![0; 60_000]].concat();
        for _ in 0..40 {
            assert!(offer("claimed", &large));
        }
        let packets = drain();
        assert_eq!(packets.len(), 17);
        assert!(
            packets
                .iter()
                .map(|packet| PREFIX.len() + packet.payload.len() + packet.claimed_peer.len())
                .sum::<usize>()
                <= 1024 * 1024
        );
        assert!(offer(
            "claimed",
            &[PREFIX, &vec![0; crate::conversation::MAX_PUBLISH_BYTES]].concat()
        ));
        assert!(
            drain().is_empty(),
            "recognized over-limit packets are dropped, never routed as calls"
        );
    }
}
