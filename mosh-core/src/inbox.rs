//! Where an inbound moss frame is filed the moment it arrives.
//!
//! One process-global queue used to hold every frame for every kind, and each
//! runtime read it by taking the whole thing, keeping the frames whose channel
//! it recognised, and putting the rest back. Three kinds, three copies of that
//! dance, none of it atomic: between one runtime's take and its put-back,
//! another runtime could take, process and return frames of its own, so the
//! first runtime's leftovers came back to the queue behind newer arrivals and
//! were read out of order. Until 0.7.4 each conversation had its own node and
//! those drains rarely overlapped; now one node carries every conversation, so
//! they overlap by design.
//!
//! So the queue is split by owner instead. A kind registers what it recognises
//! once, the moss callback files each frame under the owner that claims it,
//! and a drain takes only its own — no filtering, no leftovers, no shared
//! state to race over. Order within an owner is now a property of the
//! structure rather than of timing.
//!
//! What a channel is called stays with the kind that names it (ADR 0019): the
//! claim is a closure the kind supplies, not a table this module keeps.

use std::sync::Mutex;

use crate::moss_ffi::MossReceivedMessage;

/// Frames nobody claims still have to go somewhere: `drain_all` is how tests
/// reset the world and how `wait_for_payload` reads a raw publish, so silently
/// dropping them would make both lie. They are bounded because nothing else
/// ever reads them — an unbounded tail is a leak that only shows up after
/// hours of running.
const UNCLAIMED_CAP: usize = 256;

type Claim = Box<dyn Fn(&str) -> bool + Send + Sync>;

struct Slot {
    /// None marks the tail that holds what no owner claimed.
    claim: Option<Claim>,
    queue: Vec<MossReceivedMessage>,
}

static SLOTS: Mutex<Vec<Slot>> = Mutex::new(Vec::new());

fn slots() -> std::sync::MutexGuard<'static, Vec<Slot>> {
    // A panicking claim would poison this, and every later frame in the
    // process would be lost. The queue is plain data, so taking it back is
    // safe and infinitely better than going deaf.
    let mut guard = SLOTS.lock().unwrap_or_else(|p| p.into_inner());
    if guard.is_empty() {
        guard.push(Slot {
            claim: None,
            queue: Vec::new(),
        });
    }
    guard
}

/// One owner's queue. A kind registers once for the whole process and keeps
/// the handle; two runtimes of the same kind (two peers inside one test) share
/// it, exactly as they shared the single global queue before.
pub struct Inbox(usize);

/// Claims every channel `claim` recognises. Register before the node that
/// could deliver those frames is started — a frame that arrives before its
/// owner exists lands in the unclaimed tail and no drain will ever see it.
pub fn register(claim: impl Fn(&str) -> bool + Send + Sync + 'static) -> Inbox {
    let mut slots = slots();
    slots.push(Slot {
        claim: Some(Box::new(claim)),
        queue: Vec::new(),
    });
    Inbox(slots.len() - 1)
}

/// Files one frame under the first owner that claims it. Runs on the moss
/// callback thread, so it does no work beyond a claim check and a push.
pub fn deliver(message: MossReceivedMessage) {
    let mut slots = slots();
    let owner = slots.iter().position(|slot| {
        slot.claim
            .as_ref()
            .is_some_and(|claim| claim(&message.channel))
    });
    match owner {
        Some(index) => slots[index].queue.push(message),
        None => {
            let tail = &mut slots[0].queue;
            if tail.len() >= UNCLAIMED_CAP {
                tail.remove(0);
            }
            tail.push(message);
        }
    }
}

impl Inbox {
    /// Takes everything this owner has, oldest first.
    pub fn drain(&self) -> Vec<MossReceivedMessage> {
        std::mem::take(&mut slots()[self.0].queue)
    }
}

/// Everything every owner holds, plus what nobody claimed. This is a reset,
/// not a read: whoever calls it takes frames their owners will never see.
pub fn drain_all() -> Vec<MossReceivedMessage> {
    slots()
        .iter_mut()
        .flat_map(|slot| std::mem::take(&mut slot.queue))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::moss_ffi::MOSS_TEST_LOCK;

    fn frame(channel: &str, payload: &[u8]) -> MossReceivedMessage {
        MossReceivedMessage {
            channel: channel.to_string(),
            payload: payload.to_vec(),
        }
    }

    fn channels(messages: &[MossReceivedMessage]) -> Vec<&str> {
        messages.iter().map(|m| m.channel.as_str()).collect()
    }

    // The whole point: a drain takes its own frames and leaves everyone else's
    // where they are. Under the old shared queue this was a take-all, filter,
    // put-back — which is what let two drains reorder each other's leftovers.
    #[test]
    fn each_owner_drains_only_its_own_in_arrival_order() {
        // One process, one static registry, and `drain_all` empties every
        // slot — so these tests share the world with each other and with the
        // runtime tests, and take the same lock those do.
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let ping = register(|channel| channel.starts_with("test-ping/"));
        let pong = register(|channel| channel.starts_with("test-pong/"));

        deliver(frame("test-ping/1", b"a"));
        deliver(frame("test-pong/1", b"b"));
        deliver(frame("test-ping/2", b"c"));

        // Draining pong must not disturb ping's queue or its order.
        assert_eq!(channels(&pong.drain()), ["test-pong/1"]);
        assert_eq!(channels(&ping.drain()), ["test-ping/1", "test-ping/2"]);
        assert!(ping.drain().is_empty(), "a drained queue stays empty");

        deliver(frame("test-ping/3", b"d"));
        assert_eq!(
            channels(&ping.drain()),
            ["test-ping/3"],
            "arrivals after a drain are still this owner's"
        );
    }

    #[test]
    fn unclaimed_frames_are_kept_for_drain_all_and_bounded() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let claimed = register(|channel| channel.starts_with("test-owned/"));
        drain_all();

        deliver(frame("test-owned/1", b"mine"));
        for index in 0..UNCLAIMED_CAP + 10 {
            deliver(frame(&format!("test-nobody/{index}"), b"stray"));
        }

        let all = drain_all();
        assert!(
            all.len() <= UNCLAIMED_CAP + 1,
            "the unclaimed tail must stay bounded, got {}",
            all.len()
        );
        assert!(
            all.iter().any(|m| m.channel == "test-owned/1"),
            "drain_all is a reset: it takes the owners' queues too"
        );
        assert!(
            !all.iter().any(|m| m.channel == "test-nobody/0"),
            "the oldest stray is the one dropped at the cap"
        );
        assert!(claimed.drain().is_empty(), "drain_all already took it");
    }
}
