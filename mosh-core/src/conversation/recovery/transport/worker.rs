//! The native send can block for five seconds; it never runs on a runtime owner.
use super::{bounded::Bounded, DispatchPermit, PREFIX};
use crate::moss_ffi::MossNode;
use std::{
    sync::{Arc, Condvar, Mutex, OnceLock},
    time::{Duration, Instant},
};

struct Job {
    node: Arc<MossNode>,
    recipient: String,
    carrier: Vec<u8>,
    queued: Instant,
    permit: DispatchPermit,
}
struct Sender {
    queue: Mutex<Bounded<Job>>,
    ready: Condvar,
}
static SENDER: OnceLock<Result<Arc<Sender>, String>> = OnceLock::new();

/// Acceptance reserves bounded work only; delivery requires an authenticated reply.
pub(crate) fn enqueue(
    node: Arc<MossNode>,
    recipient: String,
    payload: Vec<u8>,
    permit: DispatchPermit,
) -> Result<(), String> {
    if !crate::conversation::recovery::manifest::canonical_hex(&recipient, 64)
        || payload.len().saturating_add(PREFIX.len()) > crate::conversation::MAX_PUBLISH_BYTES
        || !permit.is_current()
    {
        return Err("invalid directed history carrier".into());
    }
    let sender = SENDER
        .get_or_init(start_sender)
        .as_ref()
        .map_err(Clone::clone)?;
    let mut queue = sender.queue.lock().unwrap_or_else(|p| p.into_inner());
    let bytes = PREFIX.len() + payload.len() + recipient.len();
    if !queue.has_room(bytes) {
        return Err("history send queue is full".into());
    }
    let carrier = [PREFIX, payload.as_slice()].concat();
    queue.push(
        Job {
            node,
            recipient,
            carrier,
            queued: Instant::now(),
            permit,
        },
        bytes,
    );
    sender.ready.notify_one();
    Ok(())
}

fn start_sender() -> Result<Arc<Sender>, String> {
    let sender = Arc::new(Sender {
        queue: Mutex::new(Bounded::new()),
        ready: Condvar::new(),
    });
    let worker = Arc::clone(&sender);
    std::thread::Builder::new()
        .name("mosh-history-send".into())
        .spawn(move || run(worker))
        .map_err(|error| error.to_string())?;
    Ok(sender)
}

fn run(sender: Arc<Sender>) {
    loop {
        let (bytes, job) = {
            let queue = sender.queue.lock().unwrap_or_else(|p| p.into_inner());
            let mut queue = sender
                .ready
                .wait_while(queue, |queue| queue.is_empty())
                .unwrap_or_else(|p| p.into_inner());
            queue.pop().expect("the sender owns its only dequeue")
        };
        dispatch(job);
        sender
            .queue
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .complete(bytes);
    }
}

fn dispatch(job: Job) {
    if job.queued.elapsed() > Duration::from_secs(10) {
        return;
    }
    let Some(_active) = job.permit.claim() else {
        return;
    };
    // Generation locks were released by claim; only this isolated worker may block.
    if job.node.send_to_peer(&job.recipient, &job.carrier).is_err() {
        crate::diagnostics_log::write(
            crate::diagnostics_log::LogLevel::Warn,
            crate::diagnostics_log::kinds::FRAME,
            "history",
            "directed history send refused; recovery will retry",
        );
    }
}

pub(super) fn cancel_queued() {
    if let Some(Ok(sender)) = SENDER.get() {
        sender
            .queue
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .drain();
    }
}
