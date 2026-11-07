//! Bounded carrier fixture. Native send acknowledgement is still at enqueue time.
use mosh_core::moss_ffi::MossNode;
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
    mpsc::{SyncSender, sync_channel},
};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub const MAGIC: &[u8; 3] = b"MV1";
const MAX_PACKET: usize = 2007;
const MAX_AGE: Duration = Duration::from_millis(50);

#[derive(Default)]
pub struct TransportStats {
    sent: AtomicU64,
    dropped: AtomicU64,
    errors: AtomicU64,
    max_send_us: AtomicU64,
}

pub struct Transport {
    pub stats: Arc<TransportStats>,
    sender: Option<SyncSender<(Instant, Vec<u8>)>>,
    worker: Option<JoinHandle<()>>,
}

impl Transport {
    pub fn new(node: Arc<MossNode>, peer: String) -> Self {
        let (sender, receiver) = sync_channel::<(Instant, Vec<u8>)>(128);
        let stats = Arc::new(TransportStats::default());
        let measured = stats.clone();
        let worker = thread::spawn(move || {
            while let Ok((queued, packet)) = receiver.recv() {
                if queued.elapsed() > MAX_AGE {
                    measured.dropped.fetch_add(1, Ordering::Relaxed);
                    continue;
                }
                let start = Instant::now();
                let counter = if node.send_to_peer(&peer, &packet).is_ok() {
                    &measured.sent
                } else {
                    &measured.errors
                };
                counter.fetch_add(1, Ordering::Relaxed);
                measured
                    .max_send_us
                    .fetch_max(start.elapsed().as_micros() as u64, Ordering::Relaxed);
            }
        });
        Self {
            stats,
            sender: Some(sender),
            worker: Some(worker),
        }
    }

    pub fn sender(&self) -> impl Fn(Vec<u8>) + Send + Sync + 'static {
        let sender = self.sender.as_ref().unwrap().clone();
        let stats = self.stats.clone();
        move |packet| {
            if packet.len() > MAX_PACKET || sender.try_send((Instant::now(), packet)).is_err() {
                stats.dropped.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    pub fn snapshot(&self) -> Value {
        json!({ "sent": self.stats.sent.load(Ordering::Relaxed),
            "dropped": self.stats.dropped.load(Ordering::Relaxed),
            "errors": self.stats.errors.load(Ordering::Relaxed),
            "max_send_ms": self.stats.max_send_us.load(Ordering::Relaxed) as f64 / 1000.0,
            "queue_packets": 128, "max_queued_age_ms": 50,
            "native_send_timestamp": "enqueue" })
    }
}

impl Drop for Transport {
    fn drop(&mut self) {
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}
