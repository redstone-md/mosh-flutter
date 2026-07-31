//! Small in-memory reorder buffer for received voice-call frames. Direct
//! port of `src/features/private-dm/voice-call/jitter-buffer.ts` per ADR
//! 0012. Drains in seq order; pauses on a gap; once the buffered backlog
//! exceeds `gap_cap` frames it force-skips the missing seq and resumes
//! (cheap PLC).

use std::collections::BTreeMap;

/// A buffered voice frame: its wire seq and the decrypted payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BufferedFrame {
    pub seq: u64,
    pub payload: Vec<u8>,
}

/// In-memory reorder buffer. Drains frames in strictly increasing seq order,
/// pausing at a gap until the missing seq arrives, or force-skipping it once
/// the backlog grows past `gap_cap`.
#[derive(Debug)]
pub struct JitterBuffer {
    pending: BTreeMap<u64, Vec<u8>>,
    cursor: Option<u64>,
    gap_cap: usize,
}

impl JitterBuffer {
    /// New buffer with the given gap cap. The TS default is 8.
    pub fn new(gap_cap: usize) -> Self {
        Self {
            pending: BTreeMap::new(),
            cursor: None,
            gap_cap,
        }
    }

    /// Default gap cap (matches the TS `constructor(gapCap = 8)` default).
    pub fn with_default_gap_cap() -> Self {
        Self::new(8)
    }

    /// Buffered backlog (frames pending drain).
    pub fn pending_len(&self) -> usize {
        self.pending.len()
    }

    /// Current drain cursor (last seq emitted), or `None` before the first drain.
    pub fn cursor(&self) -> Option<u64> {
        self.cursor
    }

    /// Push a frame. Frames at or below the cursor (already emitted) are
    /// dropped, matching the TS `if (this.cursor !== null && frame.seq <=
    /// this.cursor) return;` guard.
    pub fn push(&mut self, frame: BufferedFrame) {
        if let Some(cursor) = self.cursor {
            if frame.seq <= cursor {
                return;
            }
        }
        self.pending.insert(frame.seq, frame.payload);
    }

    /// Drain all frames ready to play in strictly increasing seq order.
    ///
    /// Mirrors the TS `drainReady()` exactly:
    /// - If `pending` is empty, return `[]`.
    /// - Start `next` at the cursor+1, or at the lowest buffered seq if the
    ///   cursor is unset.
    /// - Emit consecutive buffered seqs, advancing the cursor, until a gap is
    ///   hit. If the remaining backlog exceeds `gap_cap`, force-skip to the
    ///   lowest remaining seq and resume; otherwise pause at the gap.
    pub fn drain_ready(&mut self) -> Vec<BufferedFrame> {
        let mut out: Vec<BufferedFrame> = Vec::new();
        if self.pending.is_empty() {
            return out;
        }
        // BTreeMap keys are already sorted ascending; `.next()` on the map
        // gives the lowest remaining seq, matching the TS `[...keys()].sort()`.
        let first = *self.pending.keys().next().unwrap();
        let mut next: u64 = self.cursor.map(|c| c + 1).unwrap_or(first);
        loop {
            if let Some(payload) = self.pending.remove(&next) {
                out.push(BufferedFrame { seq: next, payload });
                self.cursor = Some(next);
                next = next.wrapping_add(1);
                continue;
            }
            // Gap at `next`. Force-skip if backlog still exceeds the cap,
            // jumping to the lowest remaining seq (cheap PLC).
            if self.pending.len() > self.gap_cap {
                next = *self.pending.keys().next().unwrap();
                continue;
            }
            break;
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(seq: u64, payload: u8) -> BufferedFrame {
        BufferedFrame {
            seq,
            payload: vec![payload],
        }
    }

    fn seqs(drained: &[BufferedFrame]) -> Vec<u64> {
        drained.iter().map(|f| f.seq).collect()
    }

    #[test]
    fn drains_frames_in_seq_order() {
        let mut buf = JitterBuffer::with_default_gap_cap();
        buf.push(frame(2, 2));
        buf.push(frame(1, 1));
        buf.push(frame(3, 3));
        assert_eq!(seqs(&buf.drain_ready()), vec![1, 2, 3]);
    }

    #[test]
    fn drops_frames_at_or_below_the_cursor() {
        let mut buf = JitterBuffer::with_default_gap_cap();
        buf.push(frame(1, 1));
        buf.drain_ready();
        buf.push(frame(1, 1));
        assert_eq!(buf.drain_ready(), Vec::<BufferedFrame>::new());
    }

    #[test]
    fn does_not_drain_a_gap_until_the_missing_frame_arrives() {
        let mut buf = JitterBuffer::with_default_gap_cap();
        buf.push(frame(1, 1));
        buf.push(frame(3, 3));
        assert_eq!(seqs(&buf.drain_ready()), vec![1]);
        buf.push(frame(2, 2));
        assert_eq!(seqs(&buf.drain_ready()), vec![2, 3]);
    }

    #[test]
    fn force_skips_a_gap_after_the_cap_and_resumes() {
        let mut buf = JitterBuffer::new(8);
        for i in 2..=12u64 {
            buf.push(frame(i, i as u8));
        }
        let drained = buf.drain_ready();
        let seqs_out = seqs(&drained);
        assert_eq!(*seqs_out.first().unwrap(), 2);
        assert_eq!(*seqs_out.last().unwrap(), 12);
    }

    #[test]
    fn emits_strictly_increasing_seqs_across_a_forced_skip_14() {
        let mut buf = JitterBuffer::new(3);
        // gap at 2 and 3; pile enough on the far side to exceed the cap.
        buf.push(frame(1, 1));
        for i in 4..=9u64 {
            buf.push(frame(i, i as u8));
        }
        let drained = buf.drain_ready();
        let seqs_out = seqs(&drained);
        for i in 1..seqs_out.len() {
            assert!(seqs_out[i] > seqs_out[i - 1]);
        }
    }

    #[test]
    fn force_skip_jumps_to_lowest_remaining_seq_not_the_next_one() {
        // Pin the exact force-skip semantics: with cap 2, frames {1, 4, 5, 6},
        // the first drain emits 1, hits the gap at 2, and since backlog (3)
        // > cap (2), force-skips to the lowest remaining seq (4), then emits
        // 4, 5, 6. Seqs 2 and 3 are never emitted.
        let mut buf = JitterBuffer::new(2);
        buf.push(frame(1, 1));
        buf.push(frame(4, 4));
        buf.push(frame(5, 5));
        buf.push(frame(6, 6));
        assert_eq!(seqs(&buf.drain_ready()), vec![1, 4, 5, 6]);
    }

    #[test]
    fn push_replaces_an_already_pending_seqs_payload() {
        // The TS uses a Map keyed by seq; a re-push replaces the payload. The
        // Rust BTreeMap does the same, but the cursor guard drops late dupes.
        let mut buf = JitterBuffer::with_default_gap_cap();
        buf.push(frame(1, 1));
        buf.push(frame(1, 99)); // same seq, before any drain — replaces payload.
        let drained = buf.drain_ready();
        assert_eq!(seqs(&drained), vec![1]);
        assert_eq!(drained[0].payload, vec![99]);
    }

    #[test]
    fn drains_across_multiple_calls_with_a_persistent_gap() {
        let mut buf = JitterBuffer::new(2);
        buf.push(frame(1, 1));
        assert_eq!(seqs(&buf.drain_ready()), vec![1]);
        // Gap at 2; only one frame buffered -> backlog (1) <= cap (2), pause.
        buf.push(frame(3, 3));
        assert_eq!(seqs(&buf.drain_ready()), Vec::<u64>::new());
        // Backlog still equal to the cap (2) -> pause again (force-skip is
        // strictly `pending.len() > gap_cap`, matching the TS).
        buf.push(frame(4, 4));
        assert_eq!(seqs(&buf.drain_ready()), Vec::<u64>::new());
        // Now backlog (3) exceeds the cap (2) -> force-skip the gap and emit.
        buf.push(frame(5, 5));
        assert_eq!(seqs(&buf.drain_ready()), vec![3, 4, 5]);
    }
}
