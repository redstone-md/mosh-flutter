use std::time::Instant;

/// Two frames of credit absorb driver jitter without halving a 30 Hz source.
pub struct Cadence {
    last: Instant,
    credit: f64,
}
impl Cadence {
    pub fn new(now: Instant) -> Self {
        Self {
            last: now,
            credit: 1.0,
        }
    }
    pub fn accept(&mut self, now: Instant) -> bool {
        self.credit = (self.credit + now.duration_since(self.last).as_secs_f64() * 30.0).min(2.0);
        self.last = now;
        if self.credit < 1.0 {
            return false;
        }
        self.credit -= 1.0;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    #[test]
    fn processing_delay_does_not_drop_every_other_30hz_frame() {
        let now = Instant::now();
        let mut cadence = Cadence::new(now);
        let admitted = (0..30)
            .filter(|i| cadence.accept(now + Duration::from_micros(i * 33_333 + 2000)))
            .count();
        assert_eq!(admitted, 30);
        let mut cadence = Cadence::new(now);
        let admitted = (0..60)
            .filter(|i| cadence.accept(now + Duration::from_micros(i * 16_667 + 2000)))
            .count();
        assert!((30..=32).contains(&admitted));
    }
}
