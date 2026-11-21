//! Which lines a retry loop writes: the same line once per window, with the
//! repeats it held back counted on the next one written.

use std::collections::HashMap;

/// How long one line stays quiet after it is written.
pub(super) const WINDOW_SECS: u64 = 300;
/// Lines tracked at once; past this, untracked lines are written as is.
const CAPACITY: usize = 256;

#[derive(Default)]
pub(super) struct Repeats {
    lines: HashMap<String, Seen>,
}

struct Seen {
    written_at: u64,
    held: u64,
}

impl Repeats {
    /// `Some(held)` when `line` is to be written now, with how many repeats
    /// were held back since it last was; `None` while it is quiet.
    pub(super) fn admit(&mut self, line: &str, now: u64) -> Option<u64> {
        if let Some(seen) = self.lines.get_mut(line) {
            if now.saturating_sub(seen.written_at) < WINDOW_SECS {
                seen.held += 1;
                return None;
            }
            let held = seen.held;
            *seen = Seen {
                written_at: now,
                held: 0,
            };
            return Some(held);
        }
        if self.lines.len() >= CAPACITY {
            self.lines
                .retain(|_, seen| now.saturating_sub(seen.written_at) < WINDOW_SECS);
        }
        if self.lines.len() < CAPACITY {
            let seen = Seen {
                written_at: now,
                held: 0,
            };
            self.lines.insert(line.to_owned(), seen);
        }
        Some(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_line_is_written_once_per_window_and_reports_what_it_held() {
        let mut repeats = Repeats::default();
        assert_eq!(repeats.admit("deferred", 1_000), Some(0));
        assert_eq!(repeats.admit("deferred", 1_001), None);
        assert_eq!(repeats.admit("deferred", 1_000 + WINDOW_SECS - 1), None);
        assert_eq!(repeats.admit("deferred", 1_000 + WINDOW_SECS), Some(2));
        assert_eq!(repeats.admit("deferred", 1_000 + WINDOW_SECS + 1), None);
    }

    #[test]
    fn each_cause_has_its_own_window() {
        let mut repeats = Repeats::default();
        assert_eq!(repeats.admit("group-a deferred", 10), Some(0));
        assert_eq!(repeats.admit("group-b deferred", 10), Some(0));
        assert_eq!(repeats.admit("group-a dropped", 10), Some(0));
        assert_eq!(repeats.admit("group-a deferred", 11), None);
    }

    #[test]
    fn a_full_table_writes_new_lines_instead_of_losing_them() {
        let mut repeats = Repeats::default();
        for line in 0..CAPACITY {
            assert_eq!(repeats.admit(&line.to_string(), 10), Some(0));
        }
        assert_eq!(repeats.admit("untracked", 11), Some(0));
        assert_eq!(repeats.admit("untracked", 12), Some(0));
        assert_eq!(repeats.admit("0", 12), None);
        assert_eq!(repeats.admit("untracked", 10 + WINDOW_SECS), Some(0));
        assert_eq!(repeats.admit("untracked", 11 + WINDOW_SECS), None);
    }
}
