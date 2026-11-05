//! One direction of an emulated path: fixed delay, random loss and a rate
//! cap with a drop-tail queue, as a relay with a flow budget behaves.
use std::collections::VecDeque;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug)]
pub struct Shape {
    pub delay: Duration,
    pub loss: f64,
    pub rate_bps: Option<u64>,
    pub queue_bytes: usize,
}

pub struct Link {
    shape: Shape,
    /// Packets waiting for the rate cap, then for their delay.
    queue: VecDeque<Vec<u8>>,
    queued_bytes: usize,
    in_flight: VecDeque<(Instant, Vec<u8>)>,
    next_send: Instant,
    seed: u64,
    pub delivered: u64,
    pub lost: u64,
    pub overflowed: u64,
}

impl Link {
    pub fn new(shape: Shape, seed: u64) -> Self {
        Self {
            shape,
            queue: VecDeque::new(),
            queued_bytes: 0,
            in_flight: VecDeque::new(),
            next_send: Instant::now(),
            seed: seed | 1,
            delivered: 0,
            lost: 0,
            overflowed: 0,
        }
    }

    pub fn push(&mut self, packet: Vec<u8>) {
        if self.random() < self.shape.loss {
            self.lost += 1;
            return;
        }
        if self.queued_bytes + packet.len() > self.shape.queue_bytes {
            self.overflowed += 1;
            return;
        }
        self.queued_bytes += packet.len();
        self.queue.push_back(packet);
    }

    /// Packets whose delay has elapsed by `now`.
    pub fn due(&mut self, now: Instant) -> Vec<Vec<u8>> {
        while let Some(packet) = self.queue.front() {
            let start = self.next_send.max(now - Duration::from_millis(1));
            if start > now {
                break;
            }
            let bits = packet.len() as u64 * 8;
            let serialize = self.shape.rate_bps.map_or(Duration::ZERO, |rate| {
                Duration::from_secs_f64(bits as f64 / rate as f64)
            });
            self.next_send = start + serialize;
            let packet = self.queue.pop_front().unwrap();
            self.queued_bytes -= packet.len();
            self.in_flight
                .push_back((self.next_send + self.shape.delay, packet));
        }
        let mut ready = Vec::new();
        while self.in_flight.front().is_some_and(|(at, _)| *at <= now) {
            ready.push(self.in_flight.pop_front().unwrap().1);
            self.delivered += 1;
        }
        ready
    }

    fn random(&mut self) -> f64 {
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 7;
        self.seed ^= self.seed << 17;
        (self.seed >> 11) as f64 / (1u64 << 53) as f64
    }
}
