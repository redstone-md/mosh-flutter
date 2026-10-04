//! Apply commits in epoch order and recover buffered gaps.

use super::*;

#[derive(Debug, PartialEq)]
pub(super) enum SequenceOutcome {
    Done,
    /// A buffered commit exists that cannot be applied yet — the caller
    /// should request a resync.
    Gapped,
}

/// Node-free core of commit sequencing: classify by wire epoch, apply in
/// order, persist applied commits, drain any buffered successors. A commit is
/// confirmed into the dedup set ONLY after a successful apply, so a transient
/// failure or forged blob never poisons future delivery. The outcome always
/// reflects the post-apply gap state, so a still-missing predecessor triggers
/// a resync request regardless of which disposition the current commit took.
pub(super) fn sequence_commit(
    crypto: &mut MlsSessionCrypto,
    sequencer: &mut CommitSequencer,
    persistence: Option<&Persistence>,
    group_id: &str,
    commit_b64: &str,
) -> Result<SequenceOutcome, PrivateGroupError> {
    let Some(current) = crypto.epoch() else {
        return Ok(SequenceOutcome::Done);
    };
    let commit_bytes = decode(commit_b64)?;
    let wire_epoch = MlsSessionCrypto::commit_epoch(&commit_bytes)?;
    if let Disposition::Apply = sequencer.offer(current, wire_epoch, commit_b64) {
        crypto.process_commit(&commit_bytes)?;
        sequencer.confirm(commit_b64.to_string());
        log_group_commit(persistence, group_id, wire_epoch, &commit_bytes);
        // Buffered successors may be applicable now.
        while let Some(current) = crypto.epoch() {
            let Some(next_b64) = sequencer.drain_ready(current) else {
                break;
            };
            let next_bytes = decode(&next_b64)?;
            crypto.process_commit(&next_bytes)?;
            sequencer.confirm(next_b64);
            log_group_commit(persistence, group_id, current, &next_bytes);
        }
    }
    // AlreadySeen, Buffered, or Apply all end here: report whatever gap
    // remains at the (possibly advanced) current epoch.
    let stuck = crypto.epoch().is_some_and(|current| sequencer.gap(current));
    Ok(if stuck {
        SequenceOutcome::Gapped
    } else {
        SequenceOutcome::Done
    })
}

/// Feed an admin's resync replay through normal sequencing. Returns true when
/// a gap remains after the replay — the admin could not bridge it (fresh
/// state) and the member must rejoin instead of silently desyncing (spec §7).
pub(super) fn absorb_resync_commits(
    crypto: &mut MlsSessionCrypto,
    sequencer: &mut CommitSequencer,
    persistence: Option<&Persistence>,
    group_id: &str,
    commits: Vec<ResyncCommit>,
) -> bool {
    for commit in commits {
        // Per-commit tolerance: one malformed entry (a forged response can
        // splice one in) must not discard the rest of a genuine replay.
        // Duplicates and stale entries no-op inside the sequencer.
        if let Err(e) =
            sequence_commit(crypto, sequencer, persistence, group_id, &commit.commit_b64)
        {
            dlog::write(
                LogLevel::Warn,
                kinds::RESYNC,
                group_id,
                &format!("bad commit in resync replay: {e}"),
            );
        }
    }
    crypto.epoch().is_some_and(|current| sequencer.gap(current))
}

/// The deterministic successor rule: the lowest member fingerprint, ignoring
/// the departing one. The member that commits an admin's departure and every
/// member that later reads the resulting tree run this same `min()`, so they
/// agree on the new admin without a frame having to carry the answer.
pub(super) fn successor_of(members: Vec<String>, departing: &str) -> Option<String> {
    members.into_iter().filter(|fp| fp != departing).min()
}

pub(super) fn log_group_commit(
    persistence: Option<&Persistence>,
    group_id: &str,
    epoch: u64,
    commit_bytes: &[u8],
) {
    if let Some(p) = persistence {
        if let Err(e) = p.append_group_commit(group_id, epoch, commit_bytes) {
            dlog::write(
                LogLevel::Warn,
                kinds::COMMIT,
                group_id,
                &format!("commit log write failed: {e}"),
            );
        }
    }
}
