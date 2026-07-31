//! Drains pending wire frames for a voice call: decrypts each via
//! `voice_call_frame_crypto`, skips any that fail auth, reorders them through
//! `voice_call_jitter::JitterBuffer`, and feeds the ready ones to playback.
//! Direct port of `src/features/private-dm/voice-call/call-drain.ts` per
//! ADR 0012. Pure of React/Tauri so it is unit-testable and so the poll loop
//! can guard it.

use base64::Engine;

use crate::voice_call_frame_crypto::{
    open_frame_payload, FrameCryptoError, KEY_LEN, NONCE_PREFIX_LEN,
};
use crate::voice_call_jitter::{BufferedFrame, JitterBuffer};

/// Pulls pending wire frames for a call (the only gateway method this needs).
/// Mirrors the TS `CallFrameSource.callDrainFrames`, returning base64-encoded
/// wire frames — the same encoding the TS source yields over the boundary.
pub trait CallFrameSource {
    /// Fetch the pending base64 wire frames for the given session + call.
    fn call_drain_frames(&mut self, session_id: &str, call_id: &str) -> Vec<String>;
}

/// Where decoded, reordered frames go (the playback handle, narrowed).
/// Mirrors the TS `CallFrameSink.pushFrame(seq, payload)`.
pub trait CallFrameSink {
    fn push_frame(&mut self, seq: u64, payload: &[u8]);
}

/// Convenience impl so tests (and callers) can hand in a plain closure as the
/// frame source.
impl<F> CallFrameSource for F
where
    F: FnMut(&str, &str) -> Vec<String>,
{
    fn call_drain_frames(&mut self, session_id: &str, call_id: &str) -> Vec<String> {
        self(session_id, call_id)
    }
}

/// Drain pending wire frames: decode each base64 frame, decrypt via
/// `voice_call_frame_crypto` (skipping any that fail auth), push the
/// decrypted frames into `jitter`, then feed `jitter.drain_ready()` to
/// `playback` in seq order.
///
/// Pure of React/Tauri and infallible at the transport layer: malformed or
/// tampered frames are skipped, never propagated as errors.
pub fn drain_call_frames(
    source: &mut dyn CallFrameSource,
    session_id: &str,
    call_id: &str,
    key: &[u8; KEY_LEN],
    nonce_prefix: &[u8; NONCE_PREFIX_LEN],
    jitter: &mut JitterBuffer,
    playback: &mut dyn CallFrameSink,
) {
    let frames = source.call_drain_frames(session_id, call_id);
    if frames.is_empty() {
        return;
    }
    for frame_b64 in frames {
        let frame_bytes = match base64::engine::general_purpose::STANDARD.decode(&frame_b64) {
            Ok(bytes) => bytes,
            Err(_) => continue, // malformed base64 — skip, like a malformed frame.
        };
        match open_frame_payload(&frame_bytes, key, nonce_prefix) {
            Ok((seq, payload)) => jitter.push(BufferedFrame { seq, payload }),
            Err(FrameCryptoError::MalformedFrame) | Err(FrameCryptoError::AuthFailed) => {
                // Skip undecryptable frames without throwing.
            }
        }
    }
    for buffered in jitter.drain_ready() {
        playback.push_frame(buffered.seq, &buffered.payload);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::voice_call_frame_crypto::{seal_frame, CALLEE_DIRECTION_BIT};

    // KEY_B64 = "AAAA...AAAA==" -> 32 zero bytes; PREFIX_B64 = "AAAAAA==" ->
    // 4 zero bytes. The TS tests use these; the Rust port takes raw bytes.
    const KEY: [u8; KEY_LEN] = [0u8; KEY_LEN];
    const PREFIX: [u8; NONCE_PREFIX_LEN] = [0u8; NONCE_PREFIX_LEN];

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    /// Collect played frames as the single payload byte, in order — matches
    /// the TS `played: number[]` assertion shape.
    struct CaptureSink {
        played: Vec<u8>,
    }
    impl CallFrameSink for CaptureSink {
        fn push_frame(&mut self, _seq: u64, payload: &[u8]) {
            if let Some(b) = payload.first() {
                self.played.push(*b);
            }
        }
    }

    #[test]
    fn decrypts_drained_frames_and_plays_them_in_seq_order() {
        let f1 = seal_frame(1, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[10]);
        let f2 = seal_frame(2, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[20]);
        // Delivered out of order — the jitter buffer must reorder them.
        let frames = vec![b64(&f2), b64(&f1)];
        let mut source = |_: &str, _: &str| frames.clone();
        let mut jitter = JitterBuffer::with_default_gap_cap();
        let mut sink = CaptureSink { played: vec![] };

        drain_call_frames(&mut source, "s", "c", &KEY, &PREFIX, &mut jitter, &mut sink);

        assert_eq!(sink.played, vec![10, 20]);
    }

    #[test]
    fn skips_an_undecryptable_frame_without_throwing() {
        let good = seal_frame(1, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[42]);
        let mut bad = seal_frame(2, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[99]);
        let last = bad.len() - 1;
        bad[last] ^= 0xff; // tamper -> open_frame returns Err(AuthFailed)
        let frames = vec![b64(&good), b64(&bad)];
        let mut source = |_: &str, _: &str| frames.clone();
        let mut jitter = JitterBuffer::with_default_gap_cap();
        let mut sink = CaptureSink { played: vec![] };

        drain_call_frames(&mut source, "s", "c", &KEY, &PREFIX, &mut jitter, &mut sink);

        assert_eq!(sink.played, vec![42]);
    }

    #[test]
    fn skips_a_malformed_base64_frame_without_throwing() {
        // A base64 string that decodes but yields a too-short frame, plus a
        // good frame — the bad one is skipped, the good one is played.
        let good = seal_frame(5, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[7]);
        // "////" decodes to 3 bytes (0xFF,0xFF,0xFF) — below MIN_FRAME_LEN.
        let frames = vec!["////".to_string(), b64(&good)];
        let mut source = |_: &str, _: &str| frames.clone();
        let mut jitter = JitterBuffer::with_default_gap_cap();
        let mut sink = CaptureSink { played: vec![] };

        drain_call_frames(&mut source, "s", "c", &KEY, &PREFIX, &mut jitter, &mut sink);

        assert_eq!(sink.played, vec![7]);
    }

    #[test]
    fn empty_source_drains_nothing() {
        let mut source = |_: &str, _: &str| Vec::<String>::new();
        let mut jitter = JitterBuffer::with_default_gap_cap();
        let mut sink = CaptureSink { played: vec![] };

        drain_call_frames(&mut source, "s", "c", &KEY, &PREFIX, &mut jitter, &mut sink);

        assert!(sink.played.is_empty());
    }

    #[test]
    fn gap_handling_reorders_across_two_drains() {
        // Two drain calls: first plays seq 1 (gap at 2), second fills the gap
        // and plays 2, 3. Pins the jitter integration across drain boundaries.
        let f1 = seal_frame(1, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[11]);
        let f3 = seal_frame(3, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[33]);
        let f2 = seal_frame(2, CALLEE_DIRECTION_BIT, &KEY, &PREFIX, &[22]);
        let mut jitter = JitterBuffer::with_default_gap_cap();
        let mut sink = CaptureSink { played: vec![] };

        // First drain: deliver 1 and 3 (gap at 2) -> play only 1.
        let frames1 = vec![b64(&f1), b64(&f3)];
        let mut source1 = |_: &str, _: &str| frames1.clone();
        drain_call_frames(
            &mut source1,
            "s",
            "c",
            &KEY,
            &PREFIX,
            &mut jitter,
            &mut sink,
        );
        assert_eq!(sink.played, vec![11]);

        // Second drain: deliver 2 -> jitter now plays 2, 3.
        let frames2 = vec![b64(&f2)];
        let mut source2 = |_: &str, _: &str| frames2.clone();
        drain_call_frames(
            &mut source2,
            "s",
            "c",
            &KEY,
            &PREFIX,
            &mut jitter,
            &mut sink,
        );
        assert_eq!(sink.played, vec![11, 22, 33]);
    }
}
