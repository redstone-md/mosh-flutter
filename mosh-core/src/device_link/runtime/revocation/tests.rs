use super::*;
use crate::device_link::wire::{self, LinkMessage};
use crate::moss_ffi::{set_moss_keystore, MossFfiRuntime};

#[test]
fn fresh_approval_completes_after_an_early_roster_notice() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "device_link::runtime::revocation::tests::early_roster_notice_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Real Moss installation worker invoked by the signed pairing test."]
fn early_roster_notice_process() {
    let dir = std::env::temp_dir().join(format!("mosh-roster-race-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&dir).unwrap();
    let store =
        Arc::new(Persistence::open_with_dek(&dir.join("own.redb"), rand::random()).unwrap());
    set_moss_keystore(store.clone());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    moss.install_keystore().unwrap();
    let shared = SharedMossNode::new(moss);
    let mut rt = DeviceLinkRuntime::open(shared.clone(), store.clone()).unwrap();
    let key = ed25519_dalek::SigningKey::generate(&mut rand::rngs::OsRng);
    let mut trusted = DeviceIdentity::open(
        Arc::new(Persistence::open_with_dek(&dir.join("trusted.redb"), rand::random()).unwrap()),
        &hex::encode(key.verifying_key().as_bytes()),
    )
    .unwrap();
    let removed = trusted
        .roster()
        .extend(rt.identity.device().clone(), &trusted.key())
        .unwrap()
        .revoke(&rt.identity.device().device_id, &trusted.key())
        .unwrap();
    let mut record = rt.identity.record.clone();
    record.roster = removed.clone();
    rt.identity.update(record).unwrap();
    trusted.adopt_roster(removed).unwrap();

    let qr = rt.create_qr(String::new()).unwrap().qr_uri.unwrap();
    let qr = PairingQr::parse(&qr, now()).unwrap();
    let offer = wire::seal(
        &qr,
        &trusted.key(),
        LinkMessage::Offer {
            roster: trusted.roster().clone(),
            trusted: trusted.device().clone(),
        },
    )
    .unwrap();
    rt.receive(&offer).unwrap();
    let roster = trusted
        .roster()
        .extend(qr.device.clone(), &trusted.key())
        .unwrap();
    trusted.adopt_roster(roster.clone()).unwrap();
    let approved = wire::seal(
        &qr,
        &trusted.key(),
        LinkMessage::Approved {
            roster: roster.clone(),
        },
    )
    .unwrap();
    let notice =
        RosterNotice::seal(&trusted, &rt.identity.device().moss_peer_id, roster, false).unwrap();
    rt.receive(&notice).unwrap();
    assert!(
        !rt.identity.can_join().unwrap(),
        "the signed roster has already added this device"
    );
    rt.service().unwrap();
    assert_eq!(rt.phase, DeviceLinkPhase::AwaitingConfirmation);
    assert!(rt.identity.record.pending.is_some());
    drop(rt);
    let mut rt = DeviceLinkRuntime::open(shared, store).unwrap();
    assert_eq!(rt.phase, DeviceLinkPhase::AwaitingConfirmation);
    rt.receive(&approved)
        .expect("the matching fresh approval must still finish");
    assert_eq!(rt.snapshot().unwrap().phase, DeviceLinkPhase::Linked);
    assert!(rt.identity.record.pending.is_none());

    let roster = trusted
        .roster()
        .revoke(&qr.device.device_id, &trusted.key())
        .unwrap();
    trusted.adopt_roster(roster.clone()).unwrap();
    let notice =
        RosterNotice::seal(&trusted, &rt.identity.device().moss_peer_id, roster, false).unwrap();
    rt.receive(&notice).unwrap();
    rt.receive(&approved).unwrap();
    assert!(
        rt.snapshot().unwrap().revoked,
        "the consumed approval cannot restore a removed device"
    );
    drop(rt);
    std::fs::remove_dir_all(dir).unwrap();
}
