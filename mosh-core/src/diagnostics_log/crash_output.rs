//! The process's stderr, kept in a file on iOS, where nothing else keeps
//! it. Moss's Go runtime prints why it aborts there, and nowhere else, so
//! the next launch moves the file aside, shares it with the field log and
//! names the reason in a log line and, with consent, a crash report.

use std::fs;
use std::path::Path;

#[cfg(target_os = "ios")]
use super::{kinds, report_failure};

/// The live stderr of this run.
const LIVE: &str = "crash-output.log";
/// The stderr of the run before, exported with the field log.
pub(super) const PREVIOUS: &str = "crash-output.prev.log";

/// How a runtime announces that it is ending the process: Go's fatal errors
/// and panics, and Rust's panics.
const LAST_WORDS: [&str; 3] = ["fatal error:", "panic:", "panicked at"];

/// Moves the last run's output aside and sends this run's stderr to the
/// live file. Once per process: a second call would drop this run's output.
#[cfg(target_os = "ios")]
pub(super) fn capture(dir: &Path) {
    if let Some(reason) = take_previous(dir) {
        report_failure(
            kinds::STARTUP,
            "previous-run",
            &format!("the previous run ended: {reason}"),
        );
    }
    if let Ok(file) = fs::File::create(dir.join(LIVE)) {
        redirect_stderr(&file);
    }
}

#[cfg(target_os = "ios")]
fn redirect_stderr(file: &fs::File) {
    use std::os::fd::AsRawFd;
    extern "C" {
        fn dup2(from: i32, to: i32) -> i32;
    }
    // SAFETY: both descriptors are open; fd 2 now names the file, which
    // stays open through the copy after `file` is dropped.
    unsafe { dup2(file.as_raw_fd(), 2) };
}

// Only iOS captures stderr; elsewhere the tests run it.
#[cfg_attr(not(target_os = "ios"), allow(dead_code))]
/// Moves the last run's output to `PREVIOUS`, answering the line that says
/// why it ended, if it did not end quietly.
fn take_previous(dir: &Path) -> Option<String> {
    fs::create_dir_all(dir).ok()?;
    let previous = dir.join(PREVIOUS);
    fs::rename(dir.join(LIVE), &previous).ok()?;
    let output = fs::read(&previous).ok()?;
    String::from_utf8_lossy(&output)
        .lines()
        .find(|line| LAST_WORDS.iter().any(|words| line.contains(words)))
        .map(|line| line.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("mosh-crash-output-{}", rand::random::<u64>()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_run_that_aborted_names_the_reason_and_keeps_its_output() {
        let dir = dir();
        let output =
            "moss: listening\nfatal error: concurrent map writes\n\ngoroutine 7 [running]:\n";
        fs::write(dir.join(LIVE), output).unwrap();

        assert_eq!(
            take_previous(&dir).as_deref(),
            Some("fatal error: concurrent map writes")
        );
        assert_eq!(fs::read_to_string(dir.join(PREVIOUS)).unwrap(), output);
        assert!(!dir.join(LIVE).exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_quiet_run_or_a_first_launch_names_nothing() {
        let dir = dir();
        assert_eq!(take_previous(&dir), None);

        fs::write(dir.join(LIVE), "moss: listening\n").unwrap();
        assert_eq!(take_previous(&dir), None);
        fs::remove_dir_all(dir).unwrap();
    }
}
