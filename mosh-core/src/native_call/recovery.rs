use std::time::{Duration, Instant};

pub(super) fn expired(lost: &mut Option<Instant>, connected: bool, now: Instant) -> bool {
    if connected {
        *lost = None;
    } else {
        lost.get_or_insert(now);
    }
    lost.is_some_and(|at| now.saturating_duration_since(at) >= Duration::from_secs(15))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn each_connection_loss_gets_a_new_fifteen_second_recovery_window() {
        let started = Instant::now();
        let now = started + Duration::from_secs(60);
        let mut lost = None;
        assert!(!expired(&mut lost, true, now));
        assert!(!expired(&mut lost, false, now));
        assert!(!expired(&mut lost, false, now + Duration::from_secs(14)));
        assert!(expired(&mut lost, false, now + Duration::from_secs(15)));
        assert!(!expired(&mut lost, true, now + Duration::from_secs(16)));
        assert!(!expired(&mut lost, false, now + Duration::from_secs(20)));
    }
}
