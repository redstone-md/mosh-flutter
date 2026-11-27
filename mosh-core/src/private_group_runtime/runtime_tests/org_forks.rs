use super::super::org_commits::FALLBACK_COMMIT_DELAY_MS as DELAY;
use super::org_fixture::*;
use super::*;
use sha2::{Digest, Sha256};

#[test]
fn a_forked_epoch_sends_the_higher_commit_hash_to_rejoin() {
    let _guard = locked();
    let mut org = TwoAdmins::open("fork", false);
    let start = org.epoch(0);
    let departure = org.departure();
    org.deliver(0, departure.clone());
    org.deliver(1, departure);
    // Neither hears the other in time: both commit the departure.
    org.pump(0, 0);
    org.pump(1, 0);
    org.pump(1, DELAY);
    let ours = org.commit_at(0, start).unwrap();
    let theirs = org.commit_at(1, start).unwrap();
    assert_ne!(ours, theirs, "the fixture forks the tree");
    org.relay(start);
    // A redelivered duplicate must not clear the verdict.
    org.relay(start);
    let loser = usize::from(Sha256::digest(&ours) < Sha256::digest(&theirs));
    assert!(org.needs_rejoin(loser), "the higher hash rejoins");
    assert!(!org.needs_rejoin(1 - loser), "the lower hash stays");
}

/// A stale commit only counts as a fork once MLS proves an admin wrote it
/// for that epoch. Anything else must not cost a member its place: here an
/// admin relays a real commit the plain member wrote, and a resync answer
/// carries a tampered copy of ours. Both hash below ours, so either would
/// win the rule if it were taken at its word.
#[test]
fn a_forged_commit_for_a_merged_epoch_does_not_force_a_rejoin() {
    let _guard = locked();
    let mut org = TwoAdmins::open("forged", false);
    let start = org.epoch(0);
    let departure = org.departure();
    org.deliver(0, departure);
    org.pump(0, 0);
    let ours = org.commit_at(0, start).expect("a commits the departure");
    let below = |bytes: &Vec<u8>| Sha256::digest(bytes) < Sha256::digest(&ours);
    let leaver = org_signing::peer_id_hex(&org.leaver_key);
    let by_member = std::iter::repeat_with(|| {
        let mut candidate = org.member.receive_candidate().unwrap();
        candidate.remove_members_by_identity(&leaver).unwrap()
    })
    .find(below)
    .unwrap();
    let tampered = (1..ours.len())
        .map(|back| {
            let mut bytes = ours.clone();
            bytes[ours.len() - back] ^= 1;
            bytes
        })
        .find(|bytes| MlsSessionCrypto::commit_epoch(bytes).ok() == Some(start) && below(bytes))
        .unwrap();
    let relayed = ControlEnvelope::Commit {
        admission_binding: None,
        group_id: org.group_id.clone(),
        from_fingerprint: org.peers[1].clone(),
        commit_b64: encode(&by_member),
        roster_version: org.admin(1).own_roster_version(),
    };
    let answered = ControlEnvelope::ResyncResponse {
        group_id: org.group_id.clone(),
        for_fingerprint: org.admin(0).crypto.fingerprint(),
        commits: vec![ResyncCommit {
            epoch: start,
            commit_b64: encode(&tampered),
        }],
    };
    let b_key = org.keys[1].clone();
    for envelope in [relayed, answered] {
        let frame = org.signed(&b_key, &envelope);
        org.deliver(0, frame);
    }
    assert!(
        !org.needs_rejoin(0),
        "unproven commits leave the branch alone"
    );
    assert!(org.admin(0).acting_admin());
}
