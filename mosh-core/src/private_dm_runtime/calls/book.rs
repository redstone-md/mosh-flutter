use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, VecDeque};

/// Persisted ordering and terminal IDs, independent of an active media owner.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct CallProtocolBook {
    next_sequence: u64,
    received: BTreeMap<String, u64>,
    closed: VecDeque<ClosedCall>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ClosedCall {
    id: String,
    confirmed: bool,
}

impl CallProtocolBook {
    pub(super) fn allocate_sequence(&mut self) -> Option<u64> {
        self.next_sequence = self.next_sequence.checked_add(1)?;
        Some(self.next_sequence)
    }

    pub(super) fn retain_signers(&mut self, mut admitted: impl FnMut(&str) -> bool) {
        self.received.retain(|signer, _| admitted(signer));
    }

    pub(super) fn receive(&mut self, signer: &str, sequence: u64) -> bool {
        if sequence == 0
            || self
                .received
                .get(signer)
                .is_some_and(|old| *old >= sequence)
        {
            return false;
        }
        self.received.insert(signer.into(), sequence);
        true
    }

    pub(super) fn close(&mut self, id: &str, confirmed: bool) {
        if let Some(closed) = self.closed.iter_mut().find(|closed| closed.id == id) {
            closed.confirmed |= confirmed;
            return;
        }
        if self.closed.len() == 512 {
            self.closed.pop_front();
        }
        self.closed.push_back(ClosedCall {
            id: id.into(),
            confirmed,
        });
    }

    pub(super) fn closed(&self, id: &str) -> bool {
        self.closed.iter().any(|closed| closed.id == id)
    }

    pub(super) fn confirmed_closed(&self, id: &str) -> bool {
        self.closed
            .iter()
            .any(|closed| closed.id == id && closed.confirmed)
    }
}
