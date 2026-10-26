//! Short admission gates linearize cancellation without holding locks during sends.
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Execution {
    generation: u64,
    active: u32,
}
static EXECUTION: Mutex<Execution> = Mutex::new(Execution {
    generation: 0,
    active: 0,
});

#[derive(Default)]
pub(crate) struct DispatchGeneration(Arc<Mutex<u64>>);

pub(crate) struct DispatchPermit {
    owner: Arc<Mutex<u64>>,
    owner_generation: u64,
    execution_generation: u64,
}

impl DispatchGeneration {
    pub(crate) fn permit(&self) -> DispatchPermit {
        let execution = EXECUTION.lock().unwrap_or_else(|p| p.into_inner());
        let generation = self.0.lock().unwrap_or_else(|p| p.into_inner());
        DispatchPermit {
            owner: Arc::clone(&self.0),
            owner_generation: *generation,
            execution_generation: execution.generation,
        }
    }

    pub(crate) fn invalidate(&self) {
        let mut generation = self.0.lock().unwrap_or_else(|p| p.into_inner());
        *generation = generation.wrapping_add(1);
    }
}

impl DispatchPermit {
    pub(super) fn is_current(&self) -> bool {
        let execution = EXECUTION.lock().unwrap_or_else(|p| p.into_inner());
        let generation = self.owner.lock().unwrap_or_else(|p| p.into_inner());
        *generation == self.owner_generation && execution.generation == self.execution_generation
    }

    pub(super) fn claim(&self) -> Option<ActiveSend> {
        let mut execution = EXECUTION.lock().unwrap_or_else(|p| p.into_inner());
        let generation = self.owner.lock().unwrap_or_else(|p| p.into_inner());
        if *generation != self.owner_generation || execution.generation != self.execution_generation
        {
            return None;
        }
        execution.active += 1;
        Some(ActiveSend)
    }
}

pub(super) struct ActiveSend;
impl Drop for ActiveSend {
    fn drop(&mut self) {
        EXECUTION.lock().unwrap_or_else(|p| p.into_inner()).active -= 1;
    }
}

pub(super) fn cancel() {
    let mut execution = EXECUTION.lock().unwrap_or_else(|p| p.into_inner());
    execution.generation = execution.generation.wrapping_add(1);
}

pub(crate) fn active_sends() -> u32 {
    EXECUTION.lock().unwrap_or_else(|p| p.into_inner()).active
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::moss_ffi::MOSS_TEST_LOCK;
    #[test]
    fn authority_and_execution_changes_cancel_pending_permits_without_waiting_for_a_send() {
        let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let owner = DispatchGeneration::default();
        let first = owner.permit();
        owner.invalidate();
        assert!(first.claim().is_none());
        let pending = owner.permit();
        let active = owner.permit().claim().unwrap();
        assert!(active_sends() >= 1);
        cancel();
        assert!(pending.claim().is_none());
        assert!(
            active_sends() >= 1,
            "already admitted sends remain visibly draining"
        );
        drop(active);
        assert!(owner.permit().claim().is_some());
    }
}
