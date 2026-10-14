use super::{Peer, OBSERVATION_BUDGET};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

impl Peer {
    /// Waits for the runtime to report `phase`.
    pub fn wait_phase(&mut self, phase: &str) -> Value {
        self.wait_for(phase, |snapshot| snapshot["phase"] == phase)
    }

    /// A completed exchange restores as Idle; an interrupted delivery reports Linked.
    #[allow(
        dead_code,
        reason = "Used by the interrupted device-link recovery scenario"
    )]
    pub fn wait_linked_roster(&mut self, devices: &Value) -> Value {
        self.wait_for("completed link with restored roster", |snapshot| {
            matches!(snapshot["phase"].as_str(), Some("Idle" | "Linked"))
                && snapshot["error"].is_null()
                && &snapshot["devices"] == devices
        })
    }

    /// Waits for the runtime to report `error`, so a scenario observes a lost
    /// link instead of sleeping for a guessed interval.
    #[allow(
        dead_code,
        reason = "Shared harness observation the linked-desktop recovery test uses."
    )]
    pub fn wait_error(&mut self, error: &str) -> Value {
        self.wait_for(error, |snapshot| snapshot["error"] == error)
    }

    /// Polls until the expected state is observed, with a bounded deadline.
    fn wait_for(&mut self, expected: &str, ready: impl Fn(&Value) -> bool) -> Value {
        let deadline = Instant::now() + OBSERVATION_BUDGET;
        loop {
            let snapshot = self.ask(json!({"action":"snapshot"}));
            if ready(&snapshot) {
                return snapshot;
            }
            assert!(
                Instant::now() < deadline,
                "expected {expected} within {OBSERVATION_BUDGET:?}, got phase={}, error={}",
                snapshot["phase"],
                snapshot["error"]
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}
