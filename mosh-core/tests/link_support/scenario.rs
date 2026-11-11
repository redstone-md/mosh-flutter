//! Real-network scenarios: a network for each, and how long each took.

use std::cell::Cell;
use std::io::Write;
use std::sync::{Mutex, MutexGuard};
use std::time::Instant;

static LAN: Mutex<()> = Mutex::new(());
thread_local! {
    static SCOPE: Cell<u64> = const { Cell::new(0) };
}

/// The network of the scenario this thread runs: its peers find only each
/// other through the local tracker.
pub(super) fn network_scope() -> u64 {
    SCOPE.with(Cell::get)
}

/// Starts a scenario on a network of its own. Under the local tracker of
/// `scripts/moss-test.mjs` its peers find only each other, so scenarios run
/// side by side. Without the tracker they share the machine's LAN discovery
/// and take turns.
pub fn isolated_network_scenario() -> NetworkScenario {
    let shared_discovery = std::env::var_os("MOSH_TEST_TRACKER_URL").is_none();
    let turn = shared_discovery.then(|| LAN.lock().unwrap_or_else(|error| error.into_inner()));
    SCOPE.with(|scope| scope.set(rand::random()));
    super::host::watch();
    NetworkScenario {
        _turn: turn,
        started: Instant::now(),
    }
}

/// Lives as long as its scenario, then says how long that was. The test
/// harness prints a test's time only past a minute, and counts the wait for
/// a turn into it.
pub struct NetworkScenario {
    _turn: Option<MutexGuard<'static, ()>>,
    started: Instant,
}

impl Drop for NetworkScenario {
    fn drop(&mut self) {
        let thread = std::thread::current();
        // Not `eprintln!`: the harness keeps a passing test's output to itself.
        let _ = writeln!(
            std::io::stderr(),
            "scenario {} took {:.1}s",
            thread.name().unwrap_or("unnamed"),
            self.started.elapsed().as_secs_f64()
        );
    }
}
