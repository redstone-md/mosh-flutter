use super::*;
use sha2::Digest;

pub(super) fn signed_roster_order_preserves_the_remaining_client() {
    let mut f = Fixture::new();
    let mut third = identity(&f.dir, "third-own.redb");
    let roster = f
        .receiver
        .roster()
        .extend(third.device().clone(), &f.receiver.key())
        .unwrap();
    adopt(&mut f.receiver, roster.clone());
    adopt(&mut third, roster);
    let mut crypto = MlsSessionCrypto::new(&third.device().device_id).unwrap();
    let request = JoinRequest {
        request_id: "third-own".into(),
        claim: IdentityClaim::create(&third, &f.session, &crypto.signer_public(), "Own third")
            .unwrap(),
        key_package: crypto.key_package_bytes().unwrap(),
    };
    let packet = f.packet(&third, DeviceMessage::Join(request));
    f.receive(&packet).unwrap();
    let admission = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .delivery
        .as_ref()
        .unwrap()
        .admission
        .clone();
    for peer in f.peers.values_mut() {
        peer.process_commit(&admission.commit).unwrap();
    }
    crypto
        .join_welcome(&admission.welcome, &admission.tree)
        .unwrap();
    // Roster order differs from the order in which these MLS leaves joined.
    let roster = f
        .receiver
        .roster()
        .revoke(&third.device().device_id, &f.receiver.key())
        .unwrap()
        .revoke(&f.source.device().device_id, &f.receiver.key())
        .unwrap();
    adopt(&mut f.receiver, roster);
    f.snapshot();
    f.snapshot();
    let session = f.runtime.session_ref(&f.session).unwrap();
    assert_eq!(
        session.crypto.member_count(),
        2,
        "both signed removals must apply in roster order"
    );
    let removals = session.membership.as_ref().unwrap().removals.clone();
    assert_eq!(removals.len(), 2);
    assert_eq!(removals[0].evidence.target, third.device().device_id);
    assert_eq!(removals[1].evidence.target, f.source.device().device_id);
    let contact = f.peers.get_mut(&f.contact.device().device_id).unwrap();
    for removal in &removals {
        contact.process_commit(&removal.evidence.commit).unwrap();
    }
    let ciphertext = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .crypto
        .encrypt(b"remaining contact")
        .unwrap();
    assert_eq!(contact.decrypt(&ciphertext).unwrap(), b"remaining contact");
    assert!(crypto.decrypt(&ciphertext).is_err());
    assert!(f
        .peers
        .get_mut(&f.source.device().device_id)
        .unwrap()
        .decrypt(&ciphertext)
        .is_err());
    assert!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .history_import
            .is_none(),
        "an incomplete import must stop waiting for the revoked source"
    );
    for removal in removals {
        let ack = f.packet(
            &f.contact,
            DeviceMessage::RemovalAck {
                session_id: f.session.clone(),
                epoch: removal.evidence.epoch,
                evidence: hex::encode(sha2::Sha256::digest(
                    serde_json::to_vec(&removal.evidence).unwrap(),
                )),
            },
        );
        f.receive(&ack).unwrap();
    }
    assert_eq!(
        f.snapshot().device_revocation,
        Some(crate::private_dm_runtime::contracts::DmDeviceRevocationState::Applied),
        "only the remaining contact's durable acknowledgement is needed"
    );
}
