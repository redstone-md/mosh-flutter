//! Rust panic capture for opt-in crash reporting (ADR 0035).
//!
//! The `sentry` crate records each panic with its backtrace and the loaded
//! debug images, which is what lets Sentry symbolicate the call chain. It
//! sends nothing itself: a sink transport hands the event JSON to the caller,
//! and Dart scrubs it and delivers it under the same consent as its own
//! reports.
//!
//! One client lives for the process, bound to the main hub on the first
//! `start`. The switch only swaps the sink: rebinding a client would reach
//! the calling thread's hub alone, and threads that already cloned the old
//! one would keep reporting into it. With no sink, a captured panic is
//! dropped in process.

use std::sync::{Arc, Mutex, OnceLock};

type SinkFn = dyn Fn(String) + Send + Sync;

/// Receives one captured event as Sentry event JSON.
pub type EventSink = Box<SinkFn>;

// Arc so a send can clone it and release the lock before calling out: a
// panic inside the sink must not re-enter a held lock.
static SINK: Mutex<Option<Arc<SinkFn>>> = Mutex::new(None);
static CLIENT: OnceLock<()> = OnceLock::new();

struct SinkTransport;

impl sentry::Transport for SinkTransport {
    fn send_envelope(&self, envelope: sentry::Envelope) {
        let sink = SINK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone();
        let Some(sink) = sink else { return };
        if let Some(json) = envelope
            .event()
            .and_then(|event| serde_json::to_string(event).ok())
        {
            sink(json);
        }
    }
}

/// Starts delivering captured panics to `sink`, replacing an earlier sink.
/// The DSN only satisfies the client (a client without one is disabled);
/// nothing is sent to it from Rust.
pub fn start(dsn: &str, sink: EventSink) -> Result<(), String> {
    let dsn = dsn
        .parse()
        .map_err(|error| format!("invalid DSN: {error}"))?;
    *SINK.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(Arc::from(sink));
    CLIENT.get_or_init(|| {
        let mut options = sentry::ClientOptions::default();
        options.dsn = Some(dsn);
        options.transport = Some(Arc::new(Arc::new(SinkTransport)));
        options.max_breadcrumbs = 0;
        // Group by our frames, not by the capture machinery on top of them.
        options.in_app_include = vec!["mosh_core"];
        options.in_app_exclude = vec!["sentry"];
        let client = sentry::Client::from(sentry::apply_defaults(options));
        sentry::Hub::main().bind_client(Some(Arc::new(client)));
    });
    Ok(())
}

/// Stops delivering: later panics reach only the field log.
pub fn stop() {
    SINK.lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;

    const TEST_DSN: &str = "https://public@example.invalid/1";

    fn channel_sink() -> (EventSink, mpsc::Receiver<String>) {
        let (tx, rx) = mpsc::channel::<String>();
        let tx = Mutex::new(tx);
        let sink: EventSink = Box::new(move |json| {
            let _ = tx.lock().unwrap().send(json);
        });
        (sink, rx)
    }

    fn panic_on_new_thread(message: &'static str) {
        let _ = thread::spawn(move || panic!("{message}")).join();
    }

    fn captured(rx: &mpsc::Receiver<String>, message: &str) -> Option<serde_json::Value> {
        rx.try_iter()
            .map(|json| serde_json::from_str::<serde_json::Value>(&json).expect("event JSON"))
            .find(|event| event.to_string().contains(message))
    }

    // One test: the capture is process-global, so the steps must not
    // interleave with a sibling test.
    #[test]
    fn capture_follows_the_switch_from_any_thread() {
        let (sink, first) = channel_sink();
        thread::spawn(move || start(TEST_DSN, sink).expect("start"))
            .join()
            .unwrap();
        panic_on_new_thread("probe-on");
        let event = captured(&first, "probe-on").expect("a background panic is captured");
        let exception = &event["exception"]["values"][0];
        assert!(!exception["stacktrace"]["frames"]
            .as_array()
            .unwrap()
            .is_empty());
        assert!(!event["debug_meta"]["images"].as_array().unwrap().is_empty());

        stop();
        panic_on_new_thread("probe-off");
        assert!(
            captured(&first, "probe-off").is_none(),
            "nothing after opt-out"
        );

        // Re-enabling from another bridge worker thread must reach panics on
        // every thread, not only on the one that called `start`.
        let (sink, second) = channel_sink();
        thread::spawn(move || start(TEST_DSN, sink).expect("restart"))
            .join()
            .unwrap();
        panic_on_new_thread("probe-again");
        assert!(
            captured(&second, "probe-again").is_some(),
            "the new sink gets it"
        );
        stop();
    }
}
