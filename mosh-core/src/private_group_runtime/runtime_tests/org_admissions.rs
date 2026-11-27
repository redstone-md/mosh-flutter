use super::super::org_commits::FALLBACK_COMMIT_DELAY_MS as DELAY;
use super::org_fixture::*;

#[test]
fn two_online_admins_admit_a_joiner_once() {
    let _guard = locked();
    for b_designated in [false, true] {
        let mut org = TwoAdmins::open("admit-once", b_designated);
        let start = org.epoch(0);
        let joiner = org.joiner_key.clone();
        let (frame, package) = org.key_package(&joiner);
        org.deliver(0, frame.clone());
        org.deliver(1, frame);
        org.pump(0, 0);
        org.pump(1, 0);
        org.relay(start);
        // Long past every fallback: the second admin saw the Add land.
        org.pump(0, 10 * DELAY);
        org.pump(1, 10 * DELAY);
        org.relay(start);
        let landed = org.commit_at(0, start).expect("the joiner was admitted");
        assert_eq!(org.commit_at(1, start), Some(landed), "one Add, not two");
        for i in 0..2 {
            assert_eq!(org.epoch(i), start + 1);
            let crypto = &org.admin(i).crypto;
            assert!(crypto.key_package_signer_is_member(&package).unwrap());
            assert!(!org.needs_rejoin(i));
        }
    }
}

#[test]
fn the_next_admin_admits_a_joiner_only_after_its_delay() {
    let _guard = locked();
    // `b` is designated and never hears the KeyPackage.
    let mut org = TwoAdmins::open("admit-fallback", true);
    let start = org.epoch(0);
    let joiner = org.joiner_key.clone();
    let (frame, package) = org.key_package(&joiner);
    org.deliver(0, frame.clone());
    org.pump(0, 1_000);
    assert_eq!(org.epoch(0), start, "the fallback admin waits");
    // The joiner re-sends while it waits; that does not restart the clock.
    org.deliver(0, frame);
    org.pump(0, 1_000 + DELAY - 1);
    assert_eq!(org.epoch(0), start, "and not a millisecond less");
    org.pump(0, 1_000 + DELAY);
    assert_eq!(org.epoch(0), start + 1, "then admits the joiner");
    let crypto = &org.admin(0).crypto;
    assert!(crypto.key_package_signer_is_member(&package).unwrap());
}

/// An admin that lost a fork rejoins over its own stale leaf. That leaf
/// must not rank it for its own admission, or the admin left would wait.
#[test]
fn a_rejoining_admin_is_admitted_at_once_by_the_next() {
    let _guard = locked();
    // `a` sorts first and is the one rejoining.
    let mut org = TwoAdmins::open("admit-rejoin", false);
    let start = org.epoch(1);
    let rejoiner = org.keys[0].clone();
    let (frame, package) = org.key_package(&rejoiner);
    org.deliver(1, frame);
    assert_eq!(org.epoch(1), start + 1, "admitted without waiting");
    let crypto = &org.admin(1).crypto;
    assert!(crypto.key_package_signer_is_member(&package).unwrap());
    let leaves = crypto.member_identities();
    let own = leaves.iter().filter(|id| **id == org.peers[0]).count();
    assert_eq!(own, 1, "the stale leaf was replaced");
}
