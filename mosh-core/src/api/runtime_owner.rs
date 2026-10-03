//! Independent, once-built runtime owners with cached construction failures.

use std::sync::{Mutex, MutexGuard, OnceLock};

use super::conversation_bridge::ConversationBridgeError;

pub(crate) struct RuntimeOwner<T> {
    name: &'static str,
    cell: OnceLock<Result<Mutex<T>, String>>,
}

impl<T> RuntimeOwner<T> {
    pub(crate) const fn new(name: &'static str) -> Self {
        Self {
            name,
            cell: OnceLock::new(),
        }
    }

    pub(crate) fn lock<E: ToString>(
        &'static self,
        construct: impl FnOnce() -> Result<T, E>,
    ) -> Result<MutexGuard<'static, T>, ConversationBridgeError> {
        let initialized = self
            .cell
            .get_or_init(|| construct().map(Mutex::new).map_err(|e| e.to_string()));
        let mutex = initialized.as_ref().map_err(|error| {
            ConversationBridgeError::unavailable(format!(
                "{} runtime unavailable: {error}",
                self.name
            ))
        })?;
        mutex.lock().map_err(|_| {
            ConversationBridgeError::unavailable(format!("{} runtime lock poisoned", self.name))
        })
    }

    /// Service threads wait for construction and terminate on lock poison.
    pub(crate) fn initialized(&self) -> Option<&Mutex<T>> {
        self.cell.get()?.as_ref().ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn construction_and_failure_are_cached_per_owner() {
        static READY: RuntimeOwner<usize> = RuntimeOwner::new("ready");
        static FAILED: RuntimeOwner<usize> = RuntimeOwner::new("failed");
        let builds = AtomicUsize::new(0);
        assert!(READY.initialized().is_none());
        for _ in 0..2 {
            let value = READY
                .lock(|| {
                    builds.fetch_add(1, Ordering::SeqCst);
                    Ok::<_, String>(7)
                })
                .unwrap();
            assert_eq!(*value, 7);
        }
        assert_eq!(builds.load(Ordering::SeqCst), 1);
        for _ in 0..2 {
            let error = FAILED
                .lock(|| {
                    builds.fetch_add(1, Ordering::SeqCst);
                    Err::<usize, _>("load failed")
                })
                .unwrap_err();
            assert_eq!(error.message, "failed runtime unavailable: load failed");
        }
        assert_eq!(builds.load(Ordering::SeqCst), 2);
        assert!(READY.initialized().is_some());
        assert!(FAILED.initialized().is_none());
    }

    #[test]
    fn poisoned_owner_does_not_block_other_owners() {
        static POISONED: RuntimeOwner<usize> = RuntimeOwner::new("poisoned");
        static HEALTHY: RuntimeOwner<usize> = RuntimeOwner::new("healthy");
        let _ = std::thread::spawn(|| {
            let _guard = POISONED.lock(|| Ok::<_, String>(1)).unwrap();
            panic!("poison only this owner");
        })
        .join();
        let error = POISONED.lock(|| Ok::<_, String>(2)).unwrap_err();
        assert_eq!(error.message, "poisoned runtime lock poisoned");
        assert_eq!(*HEALTHY.lock(|| Ok::<_, String>(3)).unwrap(), 3);
    }
}
