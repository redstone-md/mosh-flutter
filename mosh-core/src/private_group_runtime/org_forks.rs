//! Which branch survives when two org admins committed the same epoch.
//!
//! A fork is proven by MLS and resolved by a rule both branches compute
//! alike (ADR 0005).

use super::*;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

impl GroupSession {
    /// Remember how this group left `epoch`, the state before and the commit
    /// merged, so a rival commit for it can be proven later. Org groups only.
    pub(super) fn witness_merge(&mut self, epoch: u64, before: MlsSessionCrypto, merged: &[u8]) {
        if self.org_pubkey.is_none() {
            return;
        }
        let merged = merged.to_vec();
        self.merge_witnesses
            .insert(epoch, MergeWitness { before, merged });
        while self.merge_witnesses.len() > FORK_WITNESS_EPOCHS {
            self.merge_witnesses.pop_first();
        }
    }

    /// The state to witness if `commit_b64` is about to merge at our epoch.
    pub(super) fn merge_probe(&self, commit_b64: &str) -> Option<(u64, MlsSessionCrypto)> {
        self.org_pubkey.as_ref()?;
        let epoch = MlsSessionCrypto::commit_epoch(&decode(commit_b64).ok()?).ok()?;
        (self.crypto.epoch() == Some(epoch))
            .then(|| self.crypto.receive_candidate().ok())
            .flatten()
            .map(|state| (epoch, state))
    }

    /// A commit for an epoch this session merged, with other bytes, is a fork
    /// once MLS proves it: it must stage against our state at that epoch and
    /// be signed by a leaf whose peer-id is a roster admin. Both branches keep
    /// the commit whose SHA-256 sorts lower; the one that merged the other
    /// must rejoin. Unproven bytes, epochs we never merged here and plain
    /// groups (which keep no witnesses) leave the branch alone.
    pub(super) fn note_org_fork(&mut self, commit_b64: &str) {
        if self.forked_off {
            return;
        }
        let Ok(theirs) = decode(commit_b64) else {
            return;
        };
        let Ok(epoch) = MlsSessionCrypto::commit_epoch(&theirs) else {
            return;
        };
        let Some(witness) = self.merge_witnesses.get(&epoch) else {
            return;
        };
        if witness.merged == theirs || Sha256::digest(&witness.merged) < Sha256::digest(&theirs) {
            return;
        }
        let Some(author) = witness.rival_author(&theirs) else {
            return;
        };
        if self.roster_role_is_admin(&author) {
            self.forked_off = true;
            dlog::write(
                LogLevel::Warn,
                kinds::COMMIT,
                &self.group_id,
                &format!("epoch {epoch} forked and this branch lost; rejoin needed"),
            );
        }
    }
}

/// Merged epochs kept for fork detection; an older rival goes unnoticed.
const FORK_WITNESS_EPOCHS: usize = 4;

/// How this session left one epoch: the state before it and the commit it
/// merged. In memory, so a rejoined session never judges an old branch.
pub(super) struct MergeWitness {
    before: MlsSessionCrypto,
    merged: Vec<u8>,
}

pub(super) type MergeWitnesses = BTreeMap<u64, MergeWitness>;

impl MergeWitness {
    /// Peer-id of the leaf that signed `commit`, if it is a valid commit for
    /// the witnessed epoch.
    fn rival_author(&self, commit: &[u8]) -> Option<String> {
        let staged = self.before.stage_membership(commit, None).ok()?;
        self.before.member_identity_for_signer(&staged.author)
    }
}
