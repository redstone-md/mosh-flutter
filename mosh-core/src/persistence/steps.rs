//! Steps: writes that reach the disk together.
//!
//! A commit that waits for the disk costs a sync, and a runtime makes many
//! under its lock: one sent text was thirteen (MOSH-104). Inside a step a
//! commit is readable at once and reaches the disk with the next sync: the
//! step's end, [`Persistence::sync`], or any write outside a step. A crash
//! before that leaves the store as the last sync wrote it: what survives of
//! a step is its commits up to that sync, in the order they were made.
//!
//! What a peer is told must already be on disk: a runtime syncs before a
//! frame that speaks of its writes leaves.

use super::*;
use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::{Arc, MutexGuard, PoisonError};
use std::thread::ThreadId;

/// How far the disk is behind the commits, and who is in a step.
#[derive(Default)]
pub(super) struct Disk {
    /// The threads inside a step, each with how many it has open.
    steps: HashMap<ThreadId, usize>,
    /// Whether a commit waits for the next sync.
    behind: bool,
    #[cfg(test)]
    syncs: u64,
}

impl Disk {
    fn synced(&mut self) {
        self.behind = false;
        #[cfg(test)]
        {
            self.syncs += 1;
        }
    }
}

/// A step from its start to the sync that ends it, on the thread that
/// started it.
pub(crate) struct Step(Arc<Persistence>, PhantomData<*const ()>);

impl Persistence {
    /// Starts a step on this thread: until it ends, the thread's commits to
    /// this store do not wait for the disk. A step inside a step ends with
    /// the outer one.
    pub(crate) fn step(self: &Arc<Self>) -> Step {
        *self
            .disk()
            .steps
            .entry(std::thread::current().id())
            .or_default() += 1;
        Step(Arc::clone(self), PhantomData)
    }

    /// Returns once every commit so far is on disk.
    pub(crate) fn sync(&self) -> Result<(), PersistenceError> {
        let mut disk = self.disk();
        if disk.behind {
            let tx = self.db.begin_write().map_err(db_error)?;
            Self::commit_synced(&mut disk, tx)?;
        }
        Ok(())
    }

    /// Commits `tx`, with a sync unless this thread is in a step. The caller
    /// holds the disk from before the transaction began, so commits and
    /// syncs keep one order.
    pub(super) fn commit(
        disk: &mut Disk,
        mut tx: redb::WriteTransaction,
    ) -> Result<(), PersistenceError> {
        if !disk.steps.contains_key(&std::thread::current().id()) {
            return Self::commit_synced(disk, tx);
        }
        tx.set_durability(redb::Durability::None);
        tx.commit().map_err(db_error)?;
        disk.behind = true;
        Ok(())
    }

    /// Commits `tx` with a sync, in a step or not: for a write that must be
    /// on disk when it returns. The caller holds the disk as for
    /// [`Self::commit`].
    pub(super) fn commit_synced(
        disk: &mut Disk,
        tx: redb::WriteTransaction,
    ) -> Result<(), PersistenceError> {
        tx.commit().map_err(db_error)?;
        disk.synced();
        Ok(())
    }

    pub(super) fn disk(&self) -> MutexGuard<'_, Disk> {
        self.disk.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// How many times this store has synced the disk.
    #[cfg(test)]
    pub(crate) fn syncs(&self) -> u64 {
        self.disk().syncs
    }
}

impl Drop for Step {
    fn drop(&mut self) {
        let thread = std::thread::current().id();
        {
            let mut disk = self.0.disk();
            let open = disk.steps.get_mut(&thread).expect("this thread's step");
            *open -= 1;
            if *open > 0 {
                return;
            }
            disk.steps.remove(&thread);
        }
        if let Err(error) = self.0.sync() {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                "",
                &format!("a step's writes did not reach the disk: {error}"),
            );
        }
    }
}

// test-policy: skip MOSH-104 -- Windows locks an open store against the copy these tests read as the crashed file
#[cfg(all(test, unix))]
#[path = "steps_tests.rs"]
mod tests;
