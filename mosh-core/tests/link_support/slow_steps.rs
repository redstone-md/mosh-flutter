//! Says on stderr when a step of a peer's work takes seconds.
//!
//! A parent that gives up on a command knows only that its peer stayed
//! silent. The peer's command loop and its service threads share the
//! runtimes' locks, so this names every one of them that is in a long step,
//! the one that holds a lock and those that wait for it, while the step
//! runs and again when it ends.

use std::sync::Mutex;
use std::time::{Duration, Instant};

/// A healthy step takes milliseconds.
const SLOW: Duration = Duration::from_secs(2);

struct Step {
    id: u64,
    name: String,
    started: Instant,
    /// The age at which the watch speaks of it next.
    report_at: Duration,
}

/// The steps running now, and how many have started.
struct Running {
    started: u64,
    steps: Vec<Step>,
}

static RUNNING: Mutex<Running> = Mutex::new(Running {
    started: 0,
    steps: Vec::new(),
});

/// Runs `work` as a named step of this peer.
pub(super) fn step<T>(name: &str, work: impl FnOnce() -> T) -> T {
    let _started = Started::new(name);
    work()
}

/// A step from its start to its end, whether its work returned or panicked:
/// a service thread that panics leaves its peer alive, and its step must not
/// read as still running.
struct Started(u64);

impl Started {
    fn new(name: &str) -> Self {
        let mut running = RUNNING.lock().unwrap();
        running.started += 1;
        let id = running.started;
        running.steps.push(Step {
            id,
            name: name.into(),
            started: Instant::now(),
            report_at: SLOW,
        });
        Self(id)
    }
}

impl Drop for Started {
    fn drop(&mut self) {
        let mut running = RUNNING.lock().unwrap();
        let Some(at) = running.steps.iter().position(|step| step.id == self.0) else {
            return;
        };
        let step = running.steps.swap_remove(at);
        if step.started.elapsed() >= SLOW {
            let end = if std::thread::panicking() {
                "panicked after"
            } else {
                "took"
            };
            say(&step, end);
        }
    }
}

/// Starts the thread that speaks of steps still running.
pub(super) fn watch() {
    std::thread::spawn(|| loop {
        // test-policy: wait MOSH-103 -- the watch looks at the steps' real ages twice a second
        std::thread::sleep(Duration::from_millis(500));
        for step in &mut RUNNING.lock().unwrap().steps {
            if step.started.elapsed() >= step.report_at {
                say(step, "has been running for");
                step.report_at *= 2;
            }
        }
    });
}

fn say(step: &Step, verb: &str) {
    super::say(format_args!(
        "peer {}: {} {verb} {:.1}s",
        std::process::id(),
        step.name,
        step.started.elapsed().as_secs_f64()
    ));
}

#[test]
fn a_step_whose_work_panics_is_no_longer_running() {
    let outcome = std::panic::catch_unwind(|| step("panicking step", || panic!("the work failed")));

    assert!(outcome.is_err());
    let running = RUNNING.lock().unwrap();
    assert!(running
        .steps
        .iter()
        .all(|step| step.name != "panicking step"));
}
