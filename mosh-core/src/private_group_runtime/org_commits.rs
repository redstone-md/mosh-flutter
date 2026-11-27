//! Who commits an org removal, and which branch survives when two did.
//!
//! Every roster admin may commit (ADR 0005), but gossip has no order, so two
//! admins committing the same removal fork the MLS tree. One admin is
//! designated per removal and the others only stand by; a fork that still
//! happens is proven by MLS and resolved by a rule both branches compute alike.

use super::*;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

/// How long each admin below the designated one waits before committing a
/// removal nobody has committed yet.
pub(super) const FALLBACK_COMMIT_DELAY_MS: u64 = 15_000;

/// A leaf an admin has to remove from an org group.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum RemovalTarget {
    /// A validated self-removal: that leaf, by signature key (hex).
    Leaf(String),
    /// Every leaf of a peer-id the roster no longer lists (ADR 0008).
    Identity(String),
}

impl RemovalTarget {
    fn identity(&self, crypto: &MlsSessionCrypto) -> Option<String> {
        match self {
            Self::Leaf(signer) => hex::decode(signer)
                .ok()
                .and_then(|key| crypto.member_identity_for_signer(&key)),
            Self::Identity(peer_id) => Some(peer_id.clone()),
        }
    }

    fn present(&self, crypto: &MlsSessionCrypto) -> bool {
        match self {
            Self::Leaf(signer) => crypto.member_signers().contains(signer),
            Self::Identity(peer_id) => crypto.member_identities().contains(peer_id),
        }
    }

    fn commit(&self, candidate: &mut MlsSessionCrypto) -> Result<Vec<u8>, MlsCryptoError> {
        match self {
            Self::Leaf(signer) => candidate.remove_member_by_signer(signer),
            Self::Identity(peer_id) => candidate.remove_members_by_identity(peer_id),
        }
    }
}

/// Removals waiting for this admin's turn, with the deadline stamped by the
/// first pump that saw them. In memory only: a revocation is re-derived from
/// the roster after a restart.
pub(super) type PendingRemovals = BTreeMap<RemovalTarget, Option<u64>>;

impl GroupSession {
    /// Accept an org member's departure: prove the proposal now, while its
    /// epoch is current, and commit it when this admin's turn comes.
    pub(super) fn schedule_departure(
        &mut self,
        proposal_b64: &str,
    ) -> Result<(), PrivateGroupError> {
        if !self.acting_admin() {
            return Ok(());
        }
        let signer = self.crypto.self_removal_signer(&decode(proposal_b64)?)?;
        self.schedule_removal(RemovalTarget::Leaf(signer));
        Ok(())
    }

    pub(super) fn schedule_removal(&mut self, target: RemovalTarget) {
        self.pending_removals.entry(target).or_insert(None);
    }

    /// Commit every pending removal whose turn has come. One that another
    /// admin committed first, so its leaf has left our tree, is dropped.
    pub(super) fn pump_removals(&mut self, now: u64) {
        let targets: Vec<RemovalTarget> = self.pending_removals.keys().cloned().collect();
        for target in targets {
            if self.removal_due(&target, now) {
                self.pending_removals.remove(&target);
                self.commit_removal(&target);
            }
        }
    }

    /// Stamp the deadline on first sight: rank k waits k delays. Drops a
    /// target that has left the tree or is not ours to commit.
    fn removal_due(&mut self, target: &RemovalTarget, now: u64) -> bool {
        let rank = match self.joined && target.present(&self.crypto) {
            true => self.committer_rank(target.identity(&self.crypto).as_deref()),
            false => None,
        };
        let (Some(rank), Some(deadline)) = (rank, self.pending_removals.get_mut(target)) else {
            self.pending_removals.remove(target);
            return false;
        };
        let wait = rank.saturating_mul(FALLBACK_COMMIT_DELAY_MS);
        now >= *deadline.get_or_insert(now.saturating_add(wait))
    }

    /// Our place in the commit order, mirroring `successor_of` for plain
    /// groups: roster admins holding a leaf here, by peer-id, without the
    /// member being removed. Rank 0 is the designated committer.
    fn committer_rank(&mut self, removed: Option<&str>) -> Option<u64> {
        if !self.acting_admin() {
            return None;
        }
        let own = self.own_peer_id()?;
        let roster = self.org_roster()?;
        let leaves = self.crypto.member_identities();
        let mut admins: Vec<&str> = roster
            .members
            .iter()
            .filter(|member| member.role == "admin" && leaves.contains(&member.moss_peer_id))
            .map(|member| member.moss_peer_id.as_str())
            .filter(|peer_id| Some(*peer_id) != removed)
            .collect();
        admins.sort_unstable();
        admins.dedup();
        let rank = admins.iter().position(|peer_id| *peer_id == own)?;
        u64::try_from(rank).ok()
    }

    fn commit_removal(&mut self, target: &RemovalTarget) {
        let result = self
            .crypto
            .receive_candidate()
            .map_err(PrivateGroupError::from)
            .and_then(|mut candidate| {
                let raw = target.commit(&mut candidate)?;
                self.publish_membership_change(candidate, raw)
            });
        if let Err(error) = result {
            dlog::write(
                LogLevel::Error,
                kinds::KICK,
                &self.group_id,
                &format!("org removal commit failed: {error}"),
            );
        }
    }

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
