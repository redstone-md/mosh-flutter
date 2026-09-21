//! The field log: one rotated plain file under the app-private data
//! directory.
//!
//! A release Windows build has no console, so the error lines the core used
//! to print to stderr (dropped frames, failed handshakes, stalled resends,
//! rehydrate failures) were lost. This sink carries them instead: one call,
//! one structured line per event — `timestamp level kind context message` —
//! into `<data dir>/logs/mosh.log`, rotated by size so it stays bounded.
//! Call sites never decide path or rotation policy; the sink owns both.
//!
//! The log must never break the app. Every filesystem failure is silently
//! ignored and the next write retries. Debug builds also mirror each line to
//! stderr, so a developer run still sees the old console output.

use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::api::shared_runtime::resolved_data_dir;

/// The logs directory, next to the encrypted history store.
const LOGS_DIR: &str = "logs";
/// The live log file's name.
const FILE_NAME: &str = "mosh.log";
/// The rotated copies, freshest-suffixed first: `.1` then `.2`.
const ROTATED_NAMES: [&str; 2] = ["mosh.log.1", "mosh.log.2"];
/// A file rolls once a write would push it past this size.
pub(crate) const MAX_FILE_BYTES: u64 = 2 * 1024 * 1024;
const SECONDS_PER_DAY: i64 = 86_400;

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
    pub const TEST: &str = "test";
}

/// How severe one event is. Rendered lowercase in the file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Error,
    Warn,
    Info,
}

impl LogLevel {
    fn as_str(self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Warn => "warn",
            Self::Info => "info",
        }
    }
}

impl fmt::Display for LogLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
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

/// Test-only: drop the process sink so the next write re-opens it under
/// whatever data dir the test just set. Mirrors `clear_moss_keystore`:
/// nothing outside `cfg(test)` may rebuild process state.
#[cfg(test)]
pub(crate) fn reset_sink_for_tests() {
    let mut guard = SINK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    *guard = None;
}

/// `YYYY-MM-DDTHH:MM:SSZ` for a UTC second count.
fn iso8601_utc(unix_secs: i64) -> String {
    let (year, month, day) = civil_from_days(unix_secs.div_euclid(SECONDS_PER_DAY));
    let second_of_day = unix_secs.rem_euclid(SECONDS_PER_DAY);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        second_of_day / 3600,
        (second_of_day % 3600) / 60,
        second_of_day % 60,
    )
}

fn now_unix_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs() as i64)
}

/// Days since 1970-01-01 to a civil (year, month, day); Howard Hinnant's
/// algorithm, so no time-library dependency is needed.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097) as u64;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era as i64 + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 {
        month_index + 3
    } else {
        month_index - 9
    } as u32;
    (year + i64::from(month <= 2), month, day as u32)
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
    message
        .chars()
        .map(|c| if c == '\n' || c == '\r' { ' ' } else { c })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mosh-log-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn read_lines(dir: &Path, name: &str) -> Vec<String> {
        fs::read_to_string(dir.join(name))
            .map(|text| text.lines().map(str::to_string).collect())
            .unwrap_or_default()
    }

    #[test]
    fn writes_one_structured_line_per_event() {
        let dir = temp_dir("structured");
        let mut sink = LogSink::new(dir.clone(), 10_000);
        sink.write_line(LogLevel::Error, kinds::HANDSHAKE, "s1", "handshake failed");
        sink.write_line(LogLevel::Info, kinds::TEST, "", "plain message");
        let lines = read_lines(&dir, FILE_NAME);
        assert_eq!(lines.len(), 2, "one line per event");
        let first = &lines[0];
        assert_eq!(&first[4..5], "-");
        assert_eq!(&first[10..11], "T");
        assert_eq!(&first[19..20], "Z", "ISO8601 UTC: {first}");
        assert!(
            first.contains(" error handshake s1 handshake failed"),
            "{first}"
        );
        assert!(
            lines[1].contains(" info test plain message"),
            "{}",
            lines[1]
        );
        assert!(!lines[1].contains("  "), "an empty context leaves no gap");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn renders_known_instants_as_utc() {
        assert_eq!(iso8601_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601_utc(1_700_000_000), "2023-11-14T22:13:20Z");
        assert_eq!(iso8601_utc(951_782_400), "2000-02-29T00:00:00Z");
    }

    #[test]
    fn rotates_and_keeps_every_line_across_three_files() {
        let dir = temp_dir("rotate");
        let mut sink = LogSink::new(dir.clone(), 200);
        for event in 1..=12 {
            sink.write_line(
                LogLevel::Info,
                kinds::TEST,
                "c1",
                &format!("event-{event:02}"),
            );
        }
        let live = read_lines(&dir, FILE_NAME);
        let first = read_lines(&dir, ROTATED_NAMES[0]);
        let second = read_lines(&dir, ROTATED_NAMES[1]);
        assert_eq!(
            live.len() + first.len() + second.len(),
            12,
            "nothing dropped yet"
        );
        assert!(
            second[0].contains("event-01"),
            "oldest land in .2: {second:?}"
        );
        assert!(
            first[0].contains("event-05"),
            "middle land in .1: {first:?}"
        );
        assert!(live.last().is_some_and(|l| l.contains("event-12")));
        for name in [FILE_NAME, ROTATED_NAMES[0], ROTATED_NAMES[1]] {
            if let Ok(metadata) = fs::metadata(dir.join(name)) {
                assert!(metadata.len() <= 200 + 100, "{name} grew past the cap");
            }
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn reopens_and_appends_across_instances() {
        let dir = temp_dir("reopen");
        let mut first = LogSink::new(dir.clone(), 10_000);
        first.write_line(LogLevel::Warn, kinds::TEST, "c1", "before restart");
        drop(first);
        let mut second = LogSink::new(dir.clone(), 10_000);
        second.write_line(LogLevel::Warn, kinds::TEST, "c1", "after restart");
        let lines = read_lines(&dir, FILE_NAME);
        assert_eq!(lines.len(), 2, "append keeps the previous content");
        assert!(lines[0].contains("before restart"));
        assert!(lines[1].contains("after restart"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_full_file_rotates_on_reopen() {
        let dir = temp_dir("reopen-rotate");
        let mut first = LogSink::new(dir.clone(), 60);
        first.write_line(LogLevel::Info, kinds::TEST, "c1", "one");
        drop(first);
        let mut second = LogSink::new(dir.clone(), 60);
        second.write_line(LogLevel::Info, kinds::TEST, "c1", "two");
        assert!(
            read_lines(&dir, ROTATED_NAMES[0])[0].contains("one"),
            "old moved to .1"
        );
        assert!(read_lines(&dir, FILE_NAME)[0].contains("two"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn never_panics_when_the_log_file_cannot_be_created() {
        let dir = temp_dir("blocked");
        fs::create_dir_all(dir.join(FILE_NAME)).expect("occupy the file path");
        let mut sink = LogSink::new(dir.clone(), 10_000);
        sink.write_line(LogLevel::Error, kinds::TEST, "c1", "must be dropped");
        assert_eq!(sink.ready_path(), None, "no usable file, no path to report");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_global_sink_reports_the_resolved_path() {
        // The sink freezes its directory at the FIRST process write, so an
        // earlier test could have pinned it to the default temp dir. Point
        // the data dir at a scratch root (a no-op when the once-lock already
        // holds one — the reset still wins), drop the sink, and let the
        // write below re-open it under whatever dir is in force. The
        // assertion then reads the same source of truth either way.
        let _ = crate::api::shared_runtime::set_app_data_dir(
            temp_dir("global-sink").to_string_lossy().into_owned(),
        );
        reset_sink_for_tests();
        write(LogLevel::Info, kinds::TEST, "t", "global sink smoke");
        let path = current_log_path().expect("a write opened the global sink");
        assert_eq!(path, resolved_data_dir().join(LOGS_DIR).join(FILE_NAME));
        assert!(path.is_file());
        let _ = fs::remove_dir_all(temp_dir("global-sink"));
    }
}
