//! Rust panic capture for opt-in crash reporting (ADR 0035).
//!
//! The `sentry` crate records each panic with its backtrace and the loaded
//! debug images, which is what lets Sentry symbolicate the call chain. It
//! sends nothing itself: a sink transport hands the event JSON to the caller,
//! and Dart scrubs it and delivers it under the same consent as its own
//! reports. Runs only between `start` and `stop`, i.e. while the user opted in.

use std::sync::{Arc, Mutex};

/// Receives one captured event as Sentry event JSON.
pub type EventSink = Box<dyn Fn(String) + Send + Sync>;

struct SinkTransport(EventSink);

impl sentry::Transport for SinkTransport {
    fn send_envelope(&self, envelope: sentry::Envelope) {
        if let Some(json) = envelope
            .event()
            .and_then(|event| serde_json::to_string(event).ok())
        {
            (self.0)(json);
        }
    }
}

static CLIENT: Mutex<Option<sentry::ClientInitGuard>> = Mutex::new(None);

/// Starts capturing panics into `sink`, replacing an earlier capture. The DSN
/// only satisfies the client (a client without one is disabled); nothing is
/// sent to it from Rust.
pub fn start(dsn: &str, sink: EventSink) -> Result<(), String> {
    let dsn = dsn
        .parse()
        .map_err(|error| format!("invalid DSN: {error}"))?;
    let mut options = sentry::ClientOptions::default();
    options.dsn = Some(dsn);
    options.transport = Some(Arc::new(Arc::new(SinkTransport(sink))));
    options.max_breadcrumbs = 0;
    // Group by our frames, not by the capture machinery on top of them.
    options.in_app_include = vec!["mosh_core"];
    options.in_app_exclude = vec!["sentry"];
    let guard = sentry::init(options);
    *CLIENT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(guard);
    Ok(())
}

/// Stops capturing. Dropping the guard closes the client; later panics reach
/// only the field log.
pub fn stop() {
    CLIENT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    const TEST_DSN: &str = "https://public@example.invalid/1";

    #[test]
    fn a_background_panic_arrives_with_frames_and_images_until_stopped() {
        let (tx, rx) = mpsc::channel::<String>();
        let tx = Mutex::new(tx);
        start(
            TEST_DSN,
            Box::new(move |json| {
                let _ = tx.lock().unwrap().send(json);
            }),
        )
        .expect("start");

        let _ = std::thread::spawn(|| panic!("panic-reporting-probe")).join();
        let event: serde_json::Value = rx
            .iter()
            .map(|json| serde_json::from_str(&json).expect("event JSON"))
            .find(|event: &serde_json::Value| event.to_string().contains("panic-reporting-probe"))
            .expect("the panic should be captured");
        let exception = &event["exception"]["values"][0];
        assert!(!exception["stacktrace"]["frames"]
            .as_array()
            .unwrap()
            .is_empty());
        assert!(!event["debug_meta"]["images"].as_array().unwrap().is_empty());

        stop();
        let _ = std::thread::spawn(|| panic!("panic-reporting-after-stop")).join();
        assert!(
            rx.try_iter()
                .all(|json| !json.contains("panic-reporting-after-stop")),
            "nothing is captured after opt-out"
        );
    }
}
