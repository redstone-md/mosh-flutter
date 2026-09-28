use super::*;
use openmls::prelude::Lifetime;

#[test]
fn expired_signed_epoch_recovers_and_preserves_the_admission_clock() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::devices::history::packet_tests::recovery::historical::historical_epoch_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "isolated Moss keystore worker invoked by historical epoch test"]
fn historical_epoch_process() {
    let mut f = Fixture::new();
    let admitted_ms = now_ms() - 100 * 24 * 60 * 60 * 1000;
    let admitted_seconds = admitted_ms / 1000;
    let lifetime = Lifetime::init(admitted_seconds - 60, admitted_seconds + 60);
    let admission = Lifetime::with_validation_time(admitted_seconds, || {
        next_admission_with_lifetime(&mut f, "expired.redb", "expired", Some(lifetime))
    });
    let evidence = EpochRecord::create(&f.contact, &admission, admitted_ms).unwrap();
    let source = f.source.device().clone();
    begin(&mut f, &source, admission.epoch);
    let crypto = &f.runtime.session_ref(&f.session).unwrap().crypto;
    assert!(crypto
        .key_package_identity(&admission.request.key_package)
        .is_err());
    let mut forged = evidence.clone();
    forged.admitted_at_ms = Some(admitted_ms + 1000);
    assert!(f.receive(&epoch_packet(&f, forged)).is_err());
    for corrupt_commit in [false, true] {
        let mut tampered = admission.clone();
        let bytes = if corrupt_commit {
            &mut tampered.commit
        } else {
            &mut tampered.request.key_package
        };
        *bytes.last_mut().unwrap() ^= 1;
        let tampered = EpochRecord::create(&f.contact, &tampered, admitted_ms).unwrap();
        let packet = epoch_packet(&f, tampered);
        // OpenMLS debug-asserts on failed ciphertext authentication before
        // returning its release-build error. Both paths must restore the clock.
        let refused = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f.receive(&packet)));
        assert!(refused.is_err() || refused.unwrap().is_err());
        assert!(!lifetime.is_valid());
    }
    for invalid_time in [
        0,
        admitted_ms - 60_000,
        admitted_ms + 60_000,
        now_ms() + 7_200_000,
    ] {
        let invalid = EpochRecord::create(&f.contact, &admission, invalid_time).unwrap();
        assert!(f.receive(&epoch_packet(&f, invalid)).is_err());
    }
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(2)
    );
    f.receive(&epoch_packet(&f, evidence)).unwrap();
    f.runtime.rehydrate();
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(3)
    );
    assert!(!lifetime.is_valid());
    let receiver = &mut f.runtime.session_mut(&f.session).unwrap().crypto;
    assert!(receiver
        .key_package_identity(&admission.request.key_package)
        .is_err());
    let contact = f.peers.get_mut(&f.contact.device().device_id).unwrap();
    let incoming = contact.encrypt(b"after historical recovery").unwrap();
    assert_eq!(
        receiver.decrypt(&incoming).unwrap(),
        b"after historical recovery"
    );
    let outgoing = receiver.encrypt(b"returning client replies").unwrap();
    assert_eq!(
        contact.decrypt(&outgoing).unwrap(),
        b"returning client replies"
    );
    future_time_and_lifetime_range(&mut f, admitted_seconds);
}

fn future_time_and_lifetime_range(f: &mut Fixture, historical_time: u64) {
    let admission = next_admission(f, "current.redb", "current");
    let source = f.source.device().clone();
    begin(f, &source, admission.epoch);
    let future = EpochRecord::create(&f.contact, &admission, now_ms() + 7_200_000).unwrap();
    assert!(f.receive(&epoch_packet(f, future)).is_err());
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(3)
    );
    let current = EpochRecord::create(&f.contact, &admission, now_ms()).unwrap();
    f.receive(&epoch_packet(f, current)).unwrap();
    let mut joining = MlsSessionCrypto::new("oversized-lifetime").unwrap();
    let long_lifetime = Lifetime::init(historical_time - 1, historical_time + 90 * 24 * 60 * 60);
    let package = joining.key_package_with_lifetime(long_lifetime).unwrap();
    Lifetime::with_validation_time(historical_time, || {
        let author = f.peers.get_mut(&f.contact.device().device_id).unwrap();
        assert!(author.add_members(&[&package]).is_err());
    });
    assert!(!long_lifetime.is_valid());
}
