//! One scenario on the machine's network at a time, and how long each took.

use std::cell::Cell;
use std::io::Write;
use std::sync::{Mutex, MutexGuard};
use std::time::Instant;

static NETWORK: Mutex<()> = Mutex::new(());
thread_local! {
    static SCOPE: Cell<u64> = const { Cell::new(0) };
}

/// The network of the scenario this thread runs: its peers find only each
/// other through the local tracker.
pub(super) fn network_scope() -> u64 {
    SCOPE.with(Cell::get)
}

/// Serialize LAN probes and give local-tracker scenarios independent networks.
pub fn isolated_network_scenario() -> NetworkScenario {
    let network = NETWORK.lock().unwrap_or_else(|error| error.into_inner());
    SCOPE.with(|scope| scope.set(rand::random()));
    NetworkScenario {
        _network: network,
        started: Instant::now(),
    }
}

/// Holds the network until the scenario ends, then says how long it ran. The
/// test harness times a test from its start, queue for the network included,
/// and prints that only past a minute.
pub struct NetworkScenario {
    _network: MutexGuard<'static, ()>,
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
