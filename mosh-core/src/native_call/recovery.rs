use std::time::{Duration, Instant};

/// How long a call stays up without a connected path. It covers ICE's own
/// failure timeout (about 15 seconds without packets) and the restart that
/// follows once the path returns.
const WINDOW: Duration = Duration::from_secs(30);

/// Whether the current connection loss has outlasted [`WINDOW`]; each loss
/// starts a new one.
pub(super) fn expired(lost: &mut Option<Instant>, connected: bool, now: Instant) -> bool {
    if connected {
        *lost = None;
    } else {
        lost.get_or_insert(now);
    }
    lost.is_some_and(|at| now.saturating_duration_since(at) >= WINDOW)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn each_connection_loss_gets_a_new_thirty_second_recovery_window() {
        let started = Instant::now();
        let now = started + Duration::from_secs(60);
        let mut lost = None;
        assert!(!expired(&mut lost, true, now));
        assert!(!expired(&mut lost, false, now));
        assert!(!expired(&mut lost, false, now + Duration::from_secs(29)));
        assert!(expired(&mut lost, false, now + Duration::from_secs(30)));
        assert!(!expired(&mut lost, true, now + Duration::from_secs(31)));
        assert!(!expired(&mut lost, false, now + Duration::from_secs(40)));
    }
}
