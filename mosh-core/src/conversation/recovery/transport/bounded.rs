//! Carrier budgets cover queued work and the worker's one active send.
use std::collections::VecDeque;

pub(super) struct Bounded<T> {
    items: VecDeque<(usize, T)>,
    bytes: usize,
    count: usize,
}

impl<T> Bounded<T> {
    pub(super) const fn new() -> Self {
        Self {
            items: VecDeque::new(),
            bytes: 0,
            count: 0,
        }
    }

    pub(super) fn has_room(&self, bytes: usize) -> bool {
        self.count < 32 && bytes <= (1024 * 1024_usize).saturating_sub(self.bytes)
    }

    pub(super) fn push(&mut self, item: T, bytes: usize) {
        assert!(
            self.has_room(bytes),
            "history queue admission exceeds its budget"
        );
        self.bytes += bytes;
        self.count += 1;
        self.items.push_back((bytes, item));
    }

    pub(super) fn drain(&mut self) -> Vec<T> {
        let bytes = self.items.iter().map(|(bytes, _)| bytes).sum::<usize>();
        self.bytes -= bytes;
        self.count -= self.items.len();
        self.items.drain(..).map(|(_, item)| item).collect()
    }

    pub(super) fn pop(&mut self) -> Option<(usize, T)> {
        self.items.pop_front()
    }

    pub(super) fn complete(&mut self, bytes: usize) {
        self.bytes -= bytes;
        self.count -= 1;
    }

    pub(super) fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_active_send_still_owns_its_frame_and_byte_reservation() {
        let mut queue = Bounded::new();
        for _ in 0..32 {
            queue.push((), 1);
        }
        assert!(queue.pop().is_some());
        assert!(
            !queue.has_room(1),
            "a blocked active send is still one of the 32 frames"
        );
        let mut queue = Bounded::new();
        for _ in 0..17 {
            queue.push((), 60_000);
        }
        assert!(queue.pop().is_some());
        assert!(
            !queue.has_room(60_000),
            "the active carrier still counts against 1 MiB"
        );
        queue.complete(60_000);
        assert!(queue.has_room(60_000));
    }
}
