//! A slow Moss relay call cannot stall capture, decoding or call commands.
use crate::private_dm_runtime::transport::DmTransport;
use std::{
    collections::VecDeque,
    sync::{Arc, Condvar, Mutex},
    time::{Duration, Instant},
};

struct Packet {
    peer: String,
    bytes: Vec<u8>,
    queued: Instant,
}
#[derive(Default)]
struct Queue {
    priority: VecDeque<Packet>,
    video: VecDeque<Packet>,
    stopped: bool,
    relayed: bool,
    dropped: u64,
}
struct Shared {
    queue: Mutex<Queue>,
    changed: Condvar,
}
pub(crate) struct Sender(Arc<Shared>);

impl Sender {
    pub fn new(transport: Arc<dyn DmTransport>) -> Self {
        let shared = Arc::new(Shared {
            queue: Mutex::new(Queue::default()),
            changed: Condvar::new(),
        });
        let worker = shared.clone();
        std::thread::spawn(move || send_loop(worker, transport));
        Self(shared)
    }

    pub fn enqueue(&self, peer: &str, nonce: &[u8], packet: &[u8], priority: bool) {
        if nonce.len() != 16 || packet.len() > super::library::MAX_PACKET {
            return;
        }
        let mut bytes = b"MCN1".to_vec();
        bytes.extend(nonce);
        bytes.extend(packet);
        let mut queue = self
            .0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let full = if priority {
            queue.priority.len() >= 32
        } else {
            queue.video.len() >= 96
        };
        if full {
            queue.dropped = queue.dropped.saturating_add(1);
        }
        let lane = if priority {
            &mut queue.priority
        } else {
            &mut queue.video
        };
        if full {
            lane.pop_front();
        }
        lane.push_back(Packet {
            peer: peer.into(),
            bytes,
            queued: Instant::now(),
        });
        self.0.changed.notify_one();
    }

    pub fn reset(&self) {
        let mut queue = self
            .0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        queue.priority.clear();
        queue.video.clear();
    }
    pub fn relayed(&self, relayed: bool) {
        self.0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .relayed = relayed;
    }
    pub fn dropped(&self) -> u64 {
        self.0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .dropped
    }
}
impl Drop for Sender {
    fn drop(&mut self) {
        self.0
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .stopped = true;
        self.0.changed.notify_all();
    }
}

fn send_loop(shared: Arc<Shared>, transport: Arc<dyn DmTransport>) {
    let mut total = Budget::new(48_000);
    let mut video = Budget::new(32_000);
    loop {
        let mut queue = shared
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if queue.stopped {
            return;
        }
        if queue.priority.is_empty() && queue.video.is_empty() {
            queue = shared
                .changed
                .wait_timeout(queue, Duration::from_millis(50))
                .unwrap_or_else(|error| error.into_inner())
                .0;
            if queue.stopped {
                return;
            }
        }
        let priority = !queue.priority.is_empty();
        let packet = if priority {
            queue.priority.pop_front()
        } else {
            queue.video.pop_front()
        };
        let Some(packet) = packet else {
            continue;
        };
        total.rate = if queue.relayed { 48_000 } else { 500_000 };
        video.rate = if queue.relayed { 32_000 } else { 450_000 };
        let admitted = packet.queued.elapsed() <= Duration::from_millis(50)
            && (priority || video.take(packet.bytes.len()))
            && total.take(packet.bytes.len());
        if !admitted {
            queue.dropped = queue.dropped.saturating_add(1);
        }
        drop(queue);
        if admitted
            && transport
                .send_call_packet(&packet.peer, &packet.bytes)
                .is_err()
        {
            let mut queue = shared
                .queue
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            queue.dropped = queue.dropped.saturating_add(1);
        }
    }
}

struct Budget {
    rate: usize,
    available: f64,
    updated: Instant,
}
impl Budget {
    fn new(rate: usize) -> Self {
        Self {
            rate,
            available: 0.0,
            updated: Instant::now(),
        }
    }
    fn take(&mut self, bytes: usize) -> bool {
        let now = Instant::now();
        self.available = (self.available
            + now.duration_since(self.updated).as_secs_f64() * self.rate as f64)
            .min(self.rate as f64 * 0.1);
        self.updated = now;
        if self.available < bytes as f64 {
            return false;
        }
        self.available -= bytes as f64;
        true
    }
}

pub(crate) fn unwrap<'a>(bytes: &'a [u8], nonce: &[u8]) -> Option<&'a [u8]> {
    (bytes.len() >= 27 && bytes.len() <= 2027 && &bytes[..4] == b"MCN1" && &bytes[4..20] == nonce)
        .then(|| &bytes[20..])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stale_call_nonce_and_oversized_packets_never_reach_the_engine() {
        let bytes = [b"MCN1".as_slice(), &[9; 16], b"MV1abcd"].concat();
        assert_eq!(unwrap(&bytes, &[9; 16]), Some(b"MV1abcd".as_slice()));
        assert!(unwrap(&bytes, &[8; 16]).is_none());
        assert!(unwrap(&bytes[..26], &[9; 16]).is_none());
        assert!(unwrap(&[0; 2028], &[9; 16]).is_none());
    }
}
