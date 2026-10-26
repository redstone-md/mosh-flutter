//! Four active conversations per installation, shared across kind adapters.
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Mutex, OnceLock},
};

type Slots = BTreeMap<String, BTreeSet<String>>;
fn slots() -> &'static Mutex<Slots> {
    static SLOTS: OnceLock<Mutex<Slots>> = OnceLock::new();
    SLOTS.get_or_init(Default::default)
}

pub(crate) struct ImportPermit {
    owner: String,
    conversation: String,
}
impl ImportPermit {
    pub(crate) fn acquire(owner: &str, conversation: &str) -> Option<Self> {
        let mut slots = slots().lock().unwrap_or_else(|p| p.into_inner());
        let active = slots.entry(owner.into()).or_default();
        if active.len() >= 4 || !active.insert(conversation.into()) {
            return None;
        }
        Some(Self {
            owner: owner.into(),
            conversation: conversation.into(),
        })
    }
}
impl Drop for ImportPermit {
    fn drop(&mut self) {
        let mut slots = slots().lock().unwrap_or_else(|p| p.into_inner());
        if let Some(active) = slots.get_mut(&self.owner) {
            active.remove(&self.conversation);
            if active.is_empty() {
                slots.remove(&self.owner);
            }
        }
    }
}
