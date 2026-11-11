//! Says on stderr when the machine itself stalls under a scenario.
//!
//! Every message a peer handles costs its store several synced writes, so a
//! disk that takes a second for one stretches a peer's steps into a wait's
//! whole budget. CI's Windows runners did exactly that on their system
//! drive (MOSH-103). A stalled disk or scheduler reads here as the
//! machine's, not as a peer's.

use std::io::Write;
use std::sync::Once;
use std::time::{Duration, Instant};

/// A healthy synced write takes milliseconds, and a sleep wakes on time.
const SLOW: Duration = Duration::from_millis(250);

/// Starts the watch once for the test process.
pub(super) fn watch() {
    static STARTED: Once = Once::new();
    STARTED.call_once(|| {
        std::thread::spawn(|| {
            // Beside the peers' stores, on the same drive.
            let path =
                std::env::temp_dir().join(format!("mosh-host-watch-{}", std::process::id()));
            loop {
                let slept = Instant::now();
                // test-policy: wait MOSH-103 -- the watch samples the real disk and scheduler once a second
                std::thread::sleep(Duration::from_secs(1));
                let late = slept.elapsed().saturating_sub(Duration::from_secs(1));
                let syncing = Instant::now();
                let written = std::fs::File::create(&path).and_then(|mut file| {
                    file.write_all(&[0; 4096])?;
                    file.sync_all()
                });
                let synced = syncing.elapsed();
                if late >= SLOW || synced >= SLOW || written.is_err() {
                    // Not `eprintln!`: the watch outlives the test that started it.
                    let _ = writeln!(
                        std::io::stderr(),
                        "host: a second's sleep woke {:.1}s late, a synced write took {:.1}s ({written:?})",
                        late.as_secs_f64(),
                        synced.as_secs_f64()
                    );
                }
            }
        });
    });
}
