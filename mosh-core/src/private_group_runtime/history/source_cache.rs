//! Cache only manifest summaries; frozen disk pages and live authorization stay separate.
use super::protocol::CurrentHead;
use crate::conversation::recovery::manifest::Manifest;
use std::collections::BTreeMap;

#[derive(PartialEq, Eq)]
pub(super) struct Generation {
    pub(super) messages: u64,
    pub(super) head: CurrentHead,
    pub(super) deletions: String,
}

#[derive(Default)]
pub(in crate::private_group_runtime) struct ManifestCache {
    generation: Option<Generation>,
    recipients: BTreeMap<String, Manifest>,
}

impl ManifestCache {
    pub(super) fn get(&mut self, generation: Generation, recipient: &str) -> Option<Manifest> {
        if self.generation.as_ref() != Some(&generation) {
            self.recipients.clear();
            self.generation = Some(generation);
        }
        self.recipients.get(recipient).cloned()
    }

    pub(super) fn insert(&mut self, recipient: String, manifest: Manifest) {
        if !self.recipients.contains_key(&recipient) && self.recipients.len() >= 16 {
            self.recipients.pop_first();
        }
        self.recipients.insert(recipient, manifest);
    }
}
