use crate::frb_generated::StreamSink;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex,
};

static REVISION: AtomicU64 = AtomicU64::new(0);
static SUBSCRIBER: Mutex<Option<Subscriber>> = Mutex::new(None);

struct Subscriber {
    sink: StreamSink<u64>,
    outstanding: Option<u64>,
}

pub(super) fn revision() -> u64 {
    REVISION.load(Ordering::Acquire)
}

pub(super) fn watch(sink: StreamSink<u64>) -> Result<(), String> {
    let mut subscriber = SUBSCRIBER
        .lock()
        .map_err(|_| "background subscriber unavailable")?;
    *subscriber = Some(Subscriber {
        sink,
        outstanding: None,
    });
    send(&mut subscriber);
    Ok(())
}

pub(crate) fn changed() {
    REVISION.fetch_add(1, Ordering::AcqRel);
    send(&mut SUBSCRIBER.lock().unwrap_or_else(|e| e.into_inner()));
}

/// Keep only one outstanding hint; reading durable work releases it. A newer
/// concurrent revision immediately receives one replacement, never a lost wake.
pub(super) fn consumed(observed: u64) {
    let mut subscriber = SUBSCRIBER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(current) = subscriber.as_mut() {
        if current.outstanding.is_some_and(|sent| sent <= observed) {
            current.outstanding = None;
        }
        if revision() > observed {
            send(&mut subscriber);
        }
    }
}

fn send(subscriber: &mut Option<Subscriber>) {
    let Some(current) = subscriber
        .as_mut()
        .filter(|current| current.outstanding.is_none())
    else {
        return;
    };
    let revision = revision();
    if current.sink.add(revision).is_ok() {
        current.outstanding = Some(revision);
    } else {
        *subscriber = None;
    }
}
