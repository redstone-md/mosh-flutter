use super::super::org_commits::FALLBACK_COMMIT_DELAY_MS as DELAY;
use super::org_fixture::*;
use super::*;

#[test]
fn two_online_admins_commit_a_departure_once() {
    let _guard = locked();
    for b_designated in [false, true] {
        let mut org = TwoAdmins::open("once", b_designated);
        let start = org.epoch(0);
        let leaver = org_signing::peer_id_hex(&org.leaver_key);
        let departure = org.departure();
        org.deliver(0, departure.clone());
        org.deliver(1, departure);
        org.pump(0, 0);
        org.pump(1, 0);
        org.relay(start);
        // Long past every fallback: the second admin saw the removal land.
        org.pump(0, 10 * DELAY);
        org.pump(1, 10 * DELAY);
        org.relay(start);
        assert_converged(&mut org, start, &leaver);
    }
}

#[test]
fn a_revocation_is_kicked_once_by_the_designated_admin() {
    let _guard = locked();
    for b_designated in [false, true] {
        let mut org = TwoAdmins::open("kick", b_designated);
        let start = org.epoch(0);
        let revoked = org.member_peer.clone();
        org.put_roster(2, false);
        org.pump(0, 0);
        org.pump(1, 0);
        org.relay(start);
        org.pump(0, 10 * DELAY);
        org.pump(1, 10 * DELAY);
        org.relay(start);
        let landed = org.commit_at(0, start).expect("the kick landed");
        assert_eq!(org.commit_at(1, start), Some(landed), "one kick, not two");
        for i in 0..2 {
            assert_eq!(org.epoch(i), start + 1);
            assert!(!org.admin(i).crypto.member_identities().contains(&revoked));
        }
    }
}

#[test]
fn the_next_admin_commits_a_departure_only_after_its_delay() {
    let _guard = locked();
    // `b` is designated and never hears the departure.
    let mut org = TwoAdmins::open("fallback", true);
    let start = org.epoch(0);
    let leaver = org_signing::peer_id_hex(&org.leaver_key);
    let departure = org.departure();
    org.deliver(0, departure);
    org.pump(0, 1_000);
    assert_eq!(org.epoch(0), start, "the fallback admin waits");
    org.pump(0, 1_000 + DELAY - 1);
    assert_eq!(org.epoch(0), start, "and not a millisecond less");
    org.pump(0, 1_000 + DELAY);
    assert_eq!(org.epoch(0), start + 1, "then commits the departure");
    assert!(!org.admin(0).crypto.member_identities().contains(&leaver));
}

#[test]
fn the_fallback_still_removes_the_leaver_after_an_unrelated_commit() {
    let _guard = locked();
    let mut org = TwoAdmins::open("stale", true);
    let start = org.epoch(0);
    let leaver = org_signing::peer_id_hex(&org.leaver_key);
    let departure = org.departure();
    org.deliver(0, departure);
    org.pump(0, 0);
    // `b` missed the departure but commits something else meanwhile, so the
    // leaver's proposal no longer matches the epoch.
    let mut extra = MlsSessionCrypto::new("extra").unwrap();
    let package = extra.key_package_bytes().unwrap();
    let add = org.b.crypto.add_members(&[package.as_slice()]).unwrap();
    org.b.log_commit(start, &add.commit_bytes);
    org.relay(start);
    assert_eq!(org.epoch(0), start + 1);
    org.pump(0, DELAY);
    assert_eq!(org.epoch(0), start + 2);
    assert!(!org.admin(0).crypto.member_identities().contains(&leaver));
}
