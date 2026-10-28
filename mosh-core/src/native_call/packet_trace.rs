//! Bounded numeric failure evidence for the real relay-video fixture.
use super::*;
use serde_json::{json, Value};

pub(super) struct Trace {
    started: Instant,
    previous: Instant,
    last_sample: u128,
    max_gap_ms: u128,
    max_burst_packets: usize,
    max_burst_bytes: usize,
    samples: VecDeque<Value>,
}

impl Trace {
    pub(super) fn new(started: Instant) -> Self {
        Self {
            started,
            previous: started,
            last_sample: 0,
            max_gap_ms: 0,
            max_burst_packets: 0,
            max_burst_bytes: 0,
            samples: VecDeque::new(),
        }
    }

    pub(super) fn observe(
        &mut self,
        sender: &Sender,
        captured: usize,
        decoded: u64,
        burst: (usize, usize),
    ) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.started).as_millis();
        self.max_gap_ms = self
            .max_gap_ms
            .max(now.duration_since(self.previous).as_millis());
        self.previous = now;
        self.max_burst_packets = self.max_burst_packets.max(burst.0);
        self.max_burst_bytes = self.max_burst_bytes.max(burst.1);
        if elapsed.saturating_sub(self.last_sample) < 100 {
            return;
        }
        self.last_sample = elapsed;
        let queue = sender
            .0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if self.samples.len() == 24 {
            self.samples.pop_front();
        }
        self.samples.push_back(json!({"elapsed_ms":elapsed,"captured":captured,"decoded":decoded,
            "dropped":queue.dropped,"video_queued":queue.video.len(),"priority_queued":queue.priority.len(),
            "oldest_video_ms":queue.video.front().map(|packet| now.saturating_duration_since(packet.queued).as_millis())}));
    }

    pub(super) fn snapshot(&self) -> Value {
        json!({"max_loop_gap_ms":self.max_gap_ms,"max_burst_packets":self.max_burst_packets,
            "max_burst_bytes":self.max_burst_bytes,"samples":self.samples})
    }
}
