//! Remembers which frames already arrived, so a repeat is not applied twice.
//!
//! Moss can deliver the same frame more than once, and peers re-send on
//! purpose when they think something was lost. A frame is identified by the
//! channel it came on plus the hash of its bytes. The buffer holds the last
//! few thousand of those keys and forgets the oldest, which is enough: a
//! repeat that arrives thousands of frames later is not a repeat any more.
//!
//! Which frames to run past this is the kind's decision, not the buffer's. A
//! DM, for instance, keeps its handshake and its chunk traffic out of it,
//! because there a re-send is the recovery mechanism.

use std::collections::{HashSet, VecDeque};

use crate::attachment_crypto::sha256_hex;

/// How many frame keys to keep. Roughly a session's worth of recent traffic.
const SEEN_FRAME_CAP: usize = 4096;

#[derive(Default)]
pub struct SeenFrames {
    keys: HashSet<String>,
    order: VecDeque<String>,
}

impl SeenFrames {
    /// Records a frame and says whether it had already been recorded.
    pub fn seen_before(&mut self, channel: &str, payload: &[u8]) -> bool {
        let key = format!("{channel}:{}", sha256_hex(payload));
        if !self.keys.insert(key.clone()) {
            return true;
        }
        self.order.push_back(key);
        if self.order.len() > SEEN_FRAME_CAP {
            if let Some(evicted) = self.order.pop_front() {
                self.keys.remove(&evicted);
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_same_frame_twice_is_spotted() {
        let mut seen = SeenFrames::default();

        assert!(!seen.seen_before("chat", b"hello"));
        assert!(seen.seen_before("chat", b"hello"));
    }

    #[test]
    fn the_channel_is_part_of_the_key() {
        let mut seen = SeenFrames::default();

        assert!(!seen.seen_before("chat", b"hello"));
        assert!(!seen.seen_before("blob", b"hello"));
    }

    #[test]
    fn the_oldest_key_is_forgotten_once_the_buffer_is_full() {
        let mut seen = SeenFrames::default();
        seen.seen_before("chat", b"first");
        for index in 0..SEEN_FRAME_CAP {
            seen.seen_before("chat", format!("filler-{index}").as_bytes());
        }

        // Pushed out by the filler, so it reads as new again.
        assert!(!seen.seen_before("chat", b"first"));
        // Still inside the window.
        assert!(seen.seen_before("chat", b"filler-4095"));
    }
}
