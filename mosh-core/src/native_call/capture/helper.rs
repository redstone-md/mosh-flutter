//! A camera helper process whose exit status another waiter may collect first.
//!
//! On macOS and Linux, dart:io's exit-code handler calls `wait()` for any child
//! while a Dart `Process` (the call window) lives. Our helper then reports
//! `ECHILD`: it exited with an unknown status and its pid is free for reuse, so
//! it is never signalled or waited for again.
use std::{
    fmt, io,
    process::{Child, ExitStatus},
};

/// `ECHILD` on Linux and macOS.
const ECHILD: i32 = 10;

pub(super) enum Exit {
    Status(ExitStatus),
    /// Reaped by another waiter in this process.
    Unknown,
}

impl fmt::Display for Exit {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Status(status) => status.fmt(formatter),
            Self::Unknown => formatter.write_str("status collected elsewhere"),
        }
    }
}

/// How `Helper::stop` ended the helper.
pub(super) struct Stopped {
    pub exit: io::Result<Exit>,
    /// False when the helper had already exited, so no signal was sent.
    pub killed: bool,
}

pub(super) struct Helper {
    child: Child,
    reaped: bool,
}

impl Helper {
    /// Owns a spawned child whose pipes the caller has already taken.
    pub fn new(child: Child) -> Self {
        Self {
            child,
            reaped: false,
        }
    }

    #[cfg(all(test, unix))]
    pub fn id(&self) -> u32 {
        self.child.id()
    }

    /// `Ok(None)` while the helper runs.
    pub fn try_wait(&mut self) -> io::Result<Option<Exit>> {
        if self.reaped {
            return Ok(Some(Exit::Unknown));
        }
        match self.child.try_wait() {
            Ok(status) => Ok(status.map(Exit::Status)),
            Err(error) => self.exited_elsewhere(error).map(Some),
        }
    }

    /// Kills the helper unless it is known to have exited, then waits for it.
    pub fn stop(&mut self) -> Stopped {
        if let Ok(Some(exit)) = self.try_wait() {
            return Stopped {
                exit: Ok(exit),
                killed: false,
            };
        }
        let _ = self.child.kill();
        let exit = self
            .child
            .wait()
            .map(Exit::Status)
            .or_else(|error| self.exited_elsewhere(error));
        Stopped { exit, killed: true }
    }

    /// Turns `ECHILD` into an exit with unknown status; other errors stay errors.
    fn exited_elsewhere(&mut self, error: io::Error) -> io::Result<Exit> {
        if !collected_elsewhere(&error) {
            return Err(error);
        }
        self.reaped = true;
        Ok(Exit::Unknown)
    }
}

fn collected_elsewhere(error: &io::Error) -> bool {
    // Windows has no reaping; its error 10 means something else.
    cfg!(unix) && error.raw_os_error() == Some(ECHILD)
}

/// Collects `pid` the way dart:io's exit-code handler does.
#[cfg(all(test, unix))]
pub(super) fn reap_elsewhere(pid: u32) {
    extern "C" {
        fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    }
    let mut status = 0;
    // SAFETY: `status` is a valid out-pointer and `pid` is our own child.
    assert_eq!(unsafe { waitpid(pid as i32, &mut status, 0) }, pid as i32);
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn helper_reaped_elsewhere_is_never_signalled() {
        let mut helper = Helper::new(std::process::Command::new("true").spawn().unwrap());
        reap_elsewhere(helper.id());
        assert!(matches!(helper.try_wait(), Ok(Some(Exit::Unknown))));
        let stopped = helper.stop();
        assert!(matches!(stopped.exit, Ok(Exit::Unknown)));
        assert!(
            !stopped.killed,
            "a collected pid may already belong to another process"
        );
    }

    #[test]
    fn running_helper_is_killed_and_waited_for() {
        let mut helper = Helper::new(
            std::process::Command::new("sleep")
                .arg("30")
                .spawn()
                .unwrap(),
        );
        let stopped = helper.stop();
        assert!(stopped.killed);
        assert!(matches!(stopped.exit, Ok(Exit::Status(status)) if !status.success()));
    }
}
