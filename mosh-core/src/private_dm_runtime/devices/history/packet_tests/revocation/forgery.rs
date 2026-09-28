use super::*;
use crate::private_dm_runtime::contracts::DmDeviceRevocationState;
use sha2::Digest;

fn clone_crypto(crypto: &MlsSessionCrypto) -> MlsSessionCrypto {
    MlsSessionCrypto::restore(
        "fixture",
        &crypto.signer_public(),
        &crypto.snapshot(),
        &crypto.group_id_bytes().unwrap(),
    )
    .unwrap()
}

pub(super) fn original_author_exact_leaf_and_replay() {
    let mut f = Fixture::new();
    let addition = recovery::next_admission(&mut f, "target.redb", "signed-add");
    let add = EpochRecord::create(&f.contact, &addition, now_ms()).unwrap();
    let source = f.source.device().clone();
    recovery::begin(&mut f, &source, 4);
    let packet = f.packet(
        &f.source,
        DeviceMessage::RecoveryEpoch(RecoveryEpoch {
            round: 7,
            request_id: "history-recovery-packets".into(),
            evidence: add,
        }),
    );
    f.receive(&packet).unwrap();
    let target = addition.request.claim.device_id.clone();
    let roster = f
        .contact
        .roster()
        .revoke(&target, &f.contact.key())
        .unwrap();
    let author = f.peers.get(&f.contact.device().device_id).unwrap();
    let mut proper = clone_crypto(author);
    let commit = proper
        .remove_member_by_signer(&addition.request.claim.mls_signer)
        .unwrap();
    let good = RemovalRecord::create(
        &f.contact,
        &f.session,
        target.clone(),
        roster.clone(),
        &proper,
        commit,
    )
    .unwrap();
    let mut wrong_committer = clone_crypto(f.peers.get(&f.source.device().device_id).unwrap());
    let commit = wrong_committer
        .remove_member_by_signer(&addition.request.claim.mls_signer)
        .unwrap();
    let different_committer = RemovalRecord::create(
        &f.contact,
        &f.session,
        target.clone(),
        roster.clone(),
        &wrong_committer,
        commit,
    )
    .unwrap();
    let mut wrong_leaf = clone_crypto(author);
    let receiver_signer = hex::encode(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .crypto
            .signer_public(),
    );
    let commit = wrong_leaf
        .remove_member_by_signer(&receiver_signer)
        .unwrap();
    let different_leaf = RemovalRecord::create(
        &f.contact,
        &f.session,
        target.clone(),
        roster.clone(),
        &wrong_leaf,
        commit,
    )
    .unwrap();
    let outsider = RemovalRecord::create(
        &f.outsider,
        &f.session,
        target,
        roster,
        &proper,
        good.commit.clone(),
    )
    .unwrap();
    let mut invalid = vec![different_committer, different_leaf, outsider];
    for (field, value) in [
        ("epoch", serde_json::json!(40)),
        ("group_id", serde_json::json!([9])),
        ("target", serde_json::json!(f.receiver.device().device_id)),
        ("signature", serde_json::json!("00".repeat(64))),
    ] {
        let mut changed = serde_json::to_value(&good).unwrap();
        changed[field] = value;
        invalid.push(serde_json::from_value(changed).unwrap());
    }
    let before = f.runtime.session_ref(&f.session).unwrap().crypto.snapshot();
    for evidence in invalid {
        let packet = f.packet(&f.source, DeviceMessage::Removal(evidence));
        assert!(f.receive(&packet).is_err());
        assert_eq!(
            f.runtime.session_ref(&f.session).unwrap().crypto.snapshot(),
            before
        );
    }
    let outsider_packet = f.packet(&f.outsider, DeviceMessage::Removal(good.clone()));
    assert!(f.receive(&outsider_packet).is_err());
    let packet = f.packet(&f.source, DeviceMessage::Removal(good.clone()));
    let _ = f.receive(&packet);
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(4)
    );
    assert_eq!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .crypto
            .member_count(),
        3
    );
    assert_eq!(
        f.snapshot().device_revocation,
        Some(DmDeviceRevocationState::Pending)
    );
    let digest = hex::encode(sha2::Sha256::digest(serde_json::to_vec(&good).unwrap()));
    let bad_ack = f.packet(
        &f.source,
        DeviceMessage::RemovalAck {
            session_id: f.session.clone(),
            epoch: 4,
            evidence: "00".repeat(32),
        },
    );
    assert!(f.receive(&bad_ack).is_err());
    let ack = f.packet(
        &f.source,
        DeviceMessage::RemovalAck {
            session_id: f.session.clone(),
            epoch: 4,
            evidence: digest,
        },
    );
    f.receive(&ack).unwrap();
    assert_eq!(
        f.snapshot().device_revocation,
        Some(DmDeviceRevocationState::Applied)
    );
    f.runtime.rehydrate();
    let _ = f.receive(&packet);
    assert_eq!(
        f.snapshot().device_revocation,
        Some(DmDeviceRevocationState::Applied)
    );
    let ciphertext = proper.encrypt(b"surviving client").unwrap();
    assert_eq!(
        f.runtime
            .session_mut(&f.session)
            .unwrap()
            .crypto
            .decrypt(&ciphertext)
            .unwrap(),
        b"surviving client"
    );
}
