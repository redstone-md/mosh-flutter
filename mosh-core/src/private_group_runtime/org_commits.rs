//! Who commits an org membership change.
//!
//! Every roster admin may commit (ADR 0005), but gossip has no order, so two
//! admins committing the same removal or admitting the same joiner fork the
//! MLS tree. One admin is designated per change and the others only stand
//! by; a fork that still happens is settled in `org_forks`.

use super::*;
use crate::sender_auth::SenderProof;

/// How long each admin below the designated one waits before committing a
/// change nobody has committed yet.
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

/// A joiner's KeyPackage that passed the org admission rule (ADR 0004):
/// its credential is `identity`, the roster member who sent it.
pub(super) struct Admission {
    pub(super) identity: String,
    pub(super) participant: String,
    pub(super) package: Vec<u8>,
    pub(super) joiner: Option<SenderProof>,
}

/// A membership change this admin commits when its turn comes.
pub(super) enum OrgCommit {
    Remove(RemovalTarget),
    Admit(Admission),
}

impl OrgCommit {
    /// One leaf, or one joiner: a joiner's newer KeyPackage replaces the
    /// older one, so a joiner never waits in line twice.
    fn same_change(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Remove(a), Self::Remove(b)) => a == b,
            (Self::Admit(a), Self::Admit(b)) => a.identity == b.identity,
            _ => false,
        }
    }

    /// The member the change is about, who never ranks for it.
    fn subject(&self, crypto: &MlsSessionCrypto) -> Option<String> {
        match self {
            Self::Remove(target) => target.identity(crypto),
            Self::Admit(admission) => Some(admission.identity.clone()),
        }
    }
}

/// A change waiting for this admin's turn, with the deadline stamped by the
/// first pump that saw it.
pub(super) struct PendingCommit {
    change: OrgCommit,
    deadline: Option<u64>,
}

/// In memory only: a revocation is re-derived from the roster after a
/// restart, and a joiner re-sends its KeyPackage until a Welcome arrives.
pub(super) type PendingCommits = Vec<PendingCommit>;

impl GroupSession {
    /// Accept an org member's departure: prove the proposal now, while its
    /// epoch is current, and commit it when this admin's turn comes.
    pub(super) fn schedule_departure(
        &mut self,
        proposal_b64: &str,
    ) -> Result<(), PrivateGroupError> {
        // A roster that cannot be read now is no answer; the pump asks again.
        if matches!(self.try_acting_admin(), Ok(false)) {
            return Ok(());
        }
        let signer = self.crypto.self_removal_signer(&decode(proposal_b64)?)?;
        self.schedule_commit(OrgCommit::Remove(RemovalTarget::Leaf(signer)));
        Ok(())
    }

    /// Admit an org joiner: at once when this admin is designated, so a
    /// joiner is not kept waiting by the pump, otherwise when its turn comes.
    pub(super) fn schedule_admission(
        &mut self,
        admission: Admission,
    ) -> Result<(), PrivateGroupError> {
        match self.committer_rank(Some(&admission.identity)) {
            Ok(Some(0)) => self.admit(admission),
            Ok(None) => Ok(()),
            Ok(Some(_)) | Err(_) => {
                self.schedule_commit(OrgCommit::Admit(admission));
                Ok(())
            }
        }
    }

    /// Queue a change; a repeat keeps the deadline already stamped, so a
    /// re-sent frame never pushes this admin's turn back.
    pub(super) fn schedule_commit(&mut self, change: OrgCommit) {
        let queued = self
            .pending_commits
            .iter_mut()
            .find(|pending| pending.change.same_change(&change));
        match queued {
            Some(pending) => pending.change = change,
            None => self.pending_commits.push(PendingCommit {
                change,
                deadline: None,
            }),
        }
    }

    /// Commit every pending change whose turn has come. One that another
    /// admin committed first is dropped: the leaf has left our tree, or the
    /// joiner's KeyPackage holds one. A failed roster read keeps the change
    /// for the next pump, since it says nothing about whose turn it is.
    pub(super) fn pump_commits(&mut self, now: u64) {
        let epoch = self.crypto.epoch();
        for mut pending in std::mem::take(&mut self.pending_commits) {
            match self.turn_due(&mut pending, now) {
                Ok(Some(true)) => self.commit_change(pending.change),
                Ok(Some(false)) | Err(_) => self.pending_commits.push(pending),
                Ok(None) => {}
            }
        }
        if self.crypto.epoch() != epoch {
            self.history_dispatch.invalidate();
        }
    }

    /// Stamp the deadline on first sight: rank k waits k delays. None for a
    /// change that is done or not ours to commit.
    fn turn_due(
        &mut self,
        pending: &mut PendingCommit,
        now: u64,
    ) -> Result<Option<bool>, PrivateGroupError> {
        if !self.joined || !self.outstanding(&pending.change)? {
            return Ok(None);
        }
        let subject = pending.change.subject(&self.crypto);
        let Some(rank) = self.committer_rank(subject.as_deref())? else {
            return Ok(None);
        };
        let wait = rank.saturating_mul(FALLBACK_COMMIT_DELAY_MS);
        let deadline = *pending.deadline.get_or_insert(now.saturating_add(wait));
        Ok(Some(now >= deadline))
    }

    /// Still to do: the leaf is in our tree, or the joiner is still on the
    /// roster and its KeyPackage is not. A rejoiner's stale leaf has another
    /// signer, so it does not count as admitted.
    fn outstanding(&mut self, change: &OrgCommit) -> Result<bool, PrivateGroupError> {
        match change {
            OrgCommit::Remove(target) => Ok(target.present(&self.crypto)),
            OrgCommit::Admit(admission) => {
                if self
                    .crypto
                    .key_package_signer_is_member(&admission.package)?
                {
                    return Ok(false);
                }
                let roster = self.org_roster_checked()?;
                Ok(roster
                    .members
                    .iter()
                    .any(|m| m.moss_peer_id == admission.identity))
            }
        }
    }

    /// Our place in the commit order, mirroring `successor_of` for plain
    /// groups: roster admins holding a leaf here, by peer-id, without the
    /// member the change is about. Rank 0 is the designated committer; None
    /// means not ours, an error that the roster could not be read.
    fn committer_rank(&mut self, subject: Option<&str>) -> Result<Option<u64>, PrivateGroupError> {
        if !self.try_acting_admin()? {
            return Ok(None);
        }
        let own = self.own_peer_id().ok_or(PrivateGroupError::NotReady)?;
        let roster = self.org_roster_checked()?;
        let leaves = self.crypto.member_identities();
        let mut admins: Vec<&str> = roster
            .members
            .iter()
            .filter(|member| member.role == "admin" && leaves.contains(&member.moss_peer_id))
            .map(|member| member.moss_peer_id.as_str())
            .filter(|peer_id| Some(*peer_id) != subject)
            .collect();
        admins.sort_unstable();
        admins.dedup();
        let rank = admins.iter().position(|peer_id| *peer_id == own);
        Ok(rank.and_then(|rank| u64::try_from(rank).ok()))
    }

    fn commit_change(&mut self, change: OrgCommit) {
        let (kind, result) = match change {
            OrgCommit::Remove(target) => (kinds::KICK, self.commit_removal(&target)),
            OrgCommit::Admit(admission) => (kinds::COMMIT, self.admit(admission)),
        };
        if let Err(error) = result {
            dlog::write(
                LogLevel::Error,
                kind,
                &self.group_id,
                &format!("org membership commit failed: {error}"),
            );
        }
    }

    fn commit_removal(&mut self, target: &RemovalTarget) -> Result<(), PrivateGroupError> {
        let mut candidate = self.crypto.receive_candidate()?;
        let raw = target.commit(&mut candidate)?;
        self.publish_membership_change(candidate, raw)
    }

    /// Add the joiner, replacing any stale leaf of its peer-id.
    fn admit(&mut self, admission: Admission) -> Result<(), PrivateGroupError> {
        let own_fp = self.crypto.fingerprint();
        let Admission {
            participant,
            package,
            joiner,
            ..
        } = admission;
        self.admit_history_member(participant, &package, joiner.as_ref(), own_fp)
    }
}
