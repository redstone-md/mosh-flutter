//! Bounded structured field log. Filesystem failures drop one line and retry on the next write.

use std::any::Any;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::api::shared_runtime::resolved_data_dir;
mod timestamp;
use timestamp::{iso8601_utc, now_unix_secs};

/// The logs directory, next to the encrypted history store.
const LOGS_DIR: &str = "logs";
/// The live log file's name.
const FILE_NAME: &str = "mosh.log";
/// The rotated copies, freshest-suffixed first: `.1` then `.2`.
const ROTATED_NAMES: [&str; 2] = ["mosh.log.1", "mosh.log.2"];
/// A file rolls once a write would push it past this size.
pub(crate) const MAX_FILE_BYTES: u64 = 2 * 1024 * 1024;

/// The kind slugs an event line can carry. One vocabulary, so the file stays
/// greppable; call sites pick from here instead of inventing spellings.
pub mod kinds {
    pub const REHYDRATE: &str = "rehydrate";
    pub const PERSIST: &str = "persist";
    pub const IDENTITY: &str = "identity";
    pub const PUBLISH: &str = "publish";
    pub const VERIFY: &str = "verify";
    pub const OFFER: &str = "offer";
    pub const ROOM: &str = "room";
    pub const FRAME: &str = "frame";
    pub const CONNECT: &str = "connect";
    pub const ANNOUNCE: &str = "announce";
    pub const OUTBOX: &str = "outbox";
    pub const HANDSHAKE: &str = "handshake";
    pub const DELIVERY: &str = "delivery";
    pub const RESEND: &str = "resend";
    pub const CALL: &str = "call";
    pub const COMMIT: &str = "commit";
    pub const KICK: &str = "kick";
    pub const RESYNC: &str = "resync";
    pub const VOICE: &str = "voice";
    /// The attachment chunk carrier: stream sends, fallbacks, and frames
    /// that arrive on the reserved inbox channel (spec #8).
    pub const STREAM: &str = "stream";
    /// The DM service thread that runs the protocol without a UI poll.
    pub const SERVICE: &str = "service";
    /// A Rust panic anywhere in the process, mirrored by the panic hook.
    pub const PANIC: &str = "panic";
    pub const TEST: &str = "test";
}

/// How severe one event is. Rendered lowercase in the file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Error,
    Warn,
    Info,
}

impl fmt::Display for LogLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Error => "error",
            Self::Warn => "warn",
            Self::Info => "info",
        })
    }
}

/// One logs directory and its open file. The file stays closed until the
/// first line needs it, and is dropped before renames, so rotation works on
/// Windows where an open handle cannot be renamed.
struct LogSink {
    dir: PathBuf,
    max_bytes: u64,
    dir_ready: bool,
    file: Option<(File, u64)>,
}

impl LogSink {
    /// Builds the sink; no filesystem access happens until the first line.
    fn new(dir: PathBuf, max_bytes: u64) -> Self {
        Self {
            dir,
            max_bytes,
            dir_ready: false,
            file: None,
        }
    }

    /// The live path once a write has opened the file; `None` before the
    /// first write or while the file could not be opened.
    fn ready_path(&self) -> Option<PathBuf> {
        self.file.as_ref().map(|_| self.dir.join(FILE_NAME))
    }

    /// One event: a file line first, then the stderr mirror in debug builds.
    fn write_line(&mut self, level: LogLevel, kind: &str, context_id: &str, message: &str) {
        let stamp = iso8601_utc(now_unix_secs());
        let kind = flatten(kind);
        let context = flatten(context_id);
        let message = one_line(message);
        let line = if context.is_empty() {
            format!("{stamp} {level} {kind} {message}\n")
        } else {
            format!("{stamp} {level} {kind} {context} {message}\n")
        };
        self.append(&line);
        #[cfg(debug_assertions)]
        eprintln!("{}", line.trim_end());
    }

    /// Opens the directory and file if needed, rotates a full file, and
    /// appends the line. Every failure drops the line silently.
    fn append(&mut self, line: &str) {
        if !self.dir_ready && fs::create_dir_all(&self.dir).is_err() {
            return;
        }
        self.dir_ready = true;
        if self.file.is_none() && !self.open_file() {
            return;
        }
        let full = self
            .file
            .as_ref()
            .is_some_and(|(_, len)| *len + line.len() as u64 > self.max_bytes);
        if full {
            self.rotate();
            if self.file.is_none() {
                return;
            }
        }
        if let Some((file, len)) = self.file.as_mut() {
            match file.write_all(line.as_bytes()) {
                Ok(()) => *len += line.len() as u64,
                // Forget the handle; the next line retries the open.
                Err(_) => self.file = None,
            }
        }
    }

    fn open_file(&mut self) -> bool {
        match OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.dir.join(FILE_NAME))
        {
            Ok(file) => {
                let len = file.metadata().map_or(0, |meta| meta.len());
                self.file = Some((file, len));
                true
            }
            Err(_) => false,
        }
    }

    /// Shifts `mosh.log` to `.1` and `.1` to `.2`, dropping the previous
    /// `.2`. Runs with the file closed so the renames succeed on Windows.
    fn rotate(&mut self) {
        self.file = None;
        let current = self.dir.join(FILE_NAME);
        let _ = fs::remove_file(self.dir.join(ROTATED_NAMES[1]));
        let _ = fs::rename(
            self.dir.join(ROTATED_NAMES[0]),
            self.dir.join(ROTATED_NAMES[1]),
        );
        let _ = fs::rename(&current, self.dir.join(ROTATED_NAMES[0]));
        self.open_file();
    }
}

/// The process sink. A poisoned lock is recovered, not honored: a panic
/// elsewhere while holding it must not silence the log forever.
static SINK: Mutex<Option<LogSink>> = Mutex::new(None);

fn logs_dir() -> PathBuf {
    resolved_data_dir().join(LOGS_DIR)
}

/// Writes one event line. Never fails, never panics: a filesystem failure
/// drops the line and the next write retries.
pub fn write(level: LogLevel, kind: &str, context_id: &str, message: &str) {
    let mut guard = SINK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let sink = guard.get_or_insert_with(|| LogSink::new(logs_dir(), MAX_FILE_BYTES));
    sink.write_line(level, kind, context_id, message);
}

/// Where the log lives, once a write has opened the file. `None` before the
/// first write or while the directory or file could not be created, so the
/// app offers the file only when it exists.
pub fn current_log_path() -> Option<PathBuf> {
    let guard = SINK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.as_ref()?.ready_path()
}

/// Mirror process panics into the field log, then run the existing hook.
pub fn install_panic_hook() {
    static INSTALLED: OnceLock<()> = OnceLock::new();
    let _ = INSTALLED.get_or_init(|| {
        let default_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let line = format!(
                "panic at {}: {}",
                info.location().map_or_else(
                    || "unknown location".to_string(),
                    |location| location.to_string()
                ),
                panic_payload_message(info.payload())
            );
            // try_lock: if the panic interrupted a write, this thread still
            // holds the sink mutex — skipping the line beats deadlocking the
            // abort path.
            if let Ok(mut guard) = SINK.try_lock() {
                let sink = guard.get_or_insert_with(|| LogSink::new(logs_dir(), MAX_FILE_BYTES));
                sink.write_line(LogLevel::Error, kinds::PANIC, "", &line);
            }
            default_hook(info);
        }));
    });
}

/// Unwraps a panic payload's message without assuming a `String`.
fn panic_payload_message(payload: &(dyn Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|message| (*message).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "non-string panic payload".to_string())
}

/// Reopen under the current data directory on the next test write.
#[cfg(test)]
pub(crate) fn reset_sink_for_tests() {
    let mut guard = SINK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    *guard = None;
}

/// A field that joins the line with spaces must not carry its own.
fn flatten(field: &str) -> String {
    field
        .chars()
        .map(|c| if c.is_whitespace() { '_' } else { c })
        .collect()
}

/// Messages may embed newlines from error displays; one event is one line.
fn one_line(message: &str) -> String {
    message.replace(['\n', '\r'], " ")
}

#[cfg(test)]
mod tests;
