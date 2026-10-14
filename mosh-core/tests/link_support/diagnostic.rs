use std::time::{Duration, Instant};

pub(super) fn command<T>(phase: &str, action: &str, run: impl FnOnce() -> T) -> T {
    let start = Instant::now();
    eprintln!(
        "[DEBUG-dm-command] pid={} {action} {phase} start",
        std::process::id()
    );
    let result = run();
    eprintln!(
        "[DEBUG-dm-command] pid={} {action} {phase} done {:?}",
        std::process::id(),
        start.elapsed()
    );
    result
}

pub(super) fn service(run: impl FnOnce()) {
    let start = Instant::now();
    run();
    if start.elapsed() > Duration::from_millis(250) {
        eprintln!(
            "[DEBUG-dm-command] pid={} service {:?}",
            std::process::id(),
            start.elapsed()
        );
    }
}
