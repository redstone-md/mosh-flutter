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
// Allow a 63.4 ms relay refill plus a delayed sender wakeup.
const MAX_QUEUE_AGE: Duration = Duration::from_millis(200);

pub(super) struct Capacity {
    pub total_bytes_per_second: usize,
    pub video_bytes_per_second: usize,
    pub encoder_bits_per_second: u64,
}

/// Keep engine rates below the carrier's envelope, including packet framing.
pub(super) fn capacity(relayed: bool) -> Capacity {
    if relayed {
        Capacity {
            total_bytes_per_second: 48_000,
            video_bytes_per_second: 32_000,
            encoder_bits_per_second: 224_000,
        }
    } else {
        Capacity {
            total_bytes_per_second: 500_000,
            video_bytes_per_second: 450_000,
            encoder_bits_per_second: 3_000_000,
        }
    }
}

enum Next {
    Send(Packet),
    Wait(Duration),
}
#[derive(Default)]
struct Queue {
    priority: VecDeque<Packet>,
    video: VecDeque<Packet>,
    stopped: bool,
    relayed: bool,
    dropped: u64,
}
impl Queue {
    fn lane(&mut self, priority: bool) -> &mut VecDeque<Packet> {
        if priority {
            &mut self.priority
        } else {
            &mut self.video
        }
    }

    fn next(&mut self, total: &mut Budget, video: &mut Budget, now: Instant) -> Next {
        let priority = !self.priority.is_empty();
        let Some(packet) = self.lane(priority).front() else {
            return Next::Wait(MAX_QUEUE_AGE);
        };
        let bytes = packet.bytes.len();
        let age = now.saturating_duration_since(packet.queued);
        if age >= MAX_QUEUE_AGE {
            self.lane(priority).pop_front();
            self.dropped = self.dropped.saturating_add(1);
            return Next::Wait(Duration::ZERO);
        }
        let limits = capacity(self.relayed);
        total.rate = limits.total_bytes_per_second;
        video.rate = limits.video_bytes_per_second;
        let mut wait = total.delay(bytes, now);
        if !priority {
            wait = wait.max(video.delay(bytes, now));
        }
        if !wait.is_zero() {
            return Next::Wait(wait.min(MAX_QUEUE_AGE - age));
        }
        total.available -= bytes as f64;
        if !priority {
            video.available -= bytes as f64;
        }
        Next::Send(self.lane(priority).pop_front().unwrap())
    }
}
struct Shared {
    queue: Mutex<Queue>,
    changed: Condvar,
}
pub(crate) struct Sender(Arc<Shared>);

impl Sender {
    pub fn new(transport: Arc<dyn DmTransport>) -> Self {
        let shared = Arc::new(Shared {
            queue: Mutex::new(Queue {
                relayed: true,
                ..Default::default()
            }),
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
        let lane = queue.lane(priority);
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
        self.0.changed.notify_one();
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
    let started = Instant::now();
    let limits = capacity(true);
    let mut total = Budget::new(limits.total_bytes_per_second, started);
    let mut video = Budget::new(limits.video_bytes_per_second, started);
    loop {
        let mut queue = shared
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let packet = loop {
            if queue.stopped {
                return;
            }
            if queue.priority.is_empty() && queue.video.is_empty() {
                queue = shared
                    .changed
                    .wait(queue)
                    .unwrap_or_else(|error| error.into_inner());
                continue;
            }
            match queue.next(&mut total, &mut video, Instant::now()) {
                Next::Send(packet) => break packet,
                Next::Wait(wait) => {
                    queue = shared
                        .changed
                        .wait_timeout(queue, wait)
                        .unwrap_or_else(|error| error.into_inner())
                        .0;
                }
            }
        };
        drop(queue);
        if transport
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
    fn new(rate: usize, now: Instant) -> Self {
        Self {
            rate,
            available: 0.0,
            updated: now,
        }
    }
    fn delay(&mut self, bytes: usize, now: Instant) -> Duration {
        self.available = (self.available
            + now.duration_since(self.updated).as_secs_f64() * self.rate as f64)
            .min(self.rate as f64 * 0.1);
        self.updated = now;
        if self.available < bytes as f64 {
            return Duration::from_secs_f64((bytes as f64 - self.available) / self.rate as f64);
        }
        Duration::ZERO
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

#[cfg(test)]
#[path = "packet_tests.rs"]
mod packet_tests;
