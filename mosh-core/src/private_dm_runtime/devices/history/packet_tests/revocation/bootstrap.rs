use super::*;
use crate::private_dm_runtime::devices::recovery::{RecoveryOffer, RecoveryProbe};

pub(super) fn new_client_can_relay_its_removal_of_the_original() {
    let mut f = Fixture::with_clients(false);
    let (mut joining, mut crypto, admission) =
        recovery::next_client(&mut f, "survivor.redb", "surviving-add");
    let addition = EpochRecord::create(&f.contact, &admission, now_ms()).unwrap();
    crypto
        .join_welcome(&admission.welcome, &admission.tree)
        .unwrap();
    let roster = joining
        .roster()
        .revoke(&f.contact.device().device_id, &joining.key())
        .unwrap();
    let signer = f
        .peers
        .get(&f.contact.device().device_id)
        .unwrap()
        .signer_public();
    let commit = crypto
        .remove_member_by_signer(&hex::encode(signer))
        .unwrap();
    let removal = RemovalRecord::create(
        &joining,
        &f.session,
        f.contact.device().device_id.clone(),
        roster.clone(),
        &crypto,
        commit,
    )
    .unwrap();
    adopt(&mut joining, roster);
    let packet = f.packet(&joining, DeviceMessage::Removal(removal.clone()));
    assert!(f.receive(&packet).is_err());
    f.runtime.rehydrate();
    assert_eq!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .recovery
            .as_ref()
            .expect("a signed roster extension must bootstrap the surviving new relay")
            .required_epoch,
        3
    );
    let store = f.runtime.sessions.persistence().cloned().unwrap();
    let packets = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .recovery_packets(&store, now_ms() + 5_001)
        .unwrap();
    assert!(
        packets
            .iter()
            .all(|(peer, _)| peer != &f.contact.device().moss_peer_id),
        "the removed original must not be a recovery candidate"
    );
    let probe = packets
        .into_iter()
        .find_map(|(peer, message)| match message {
            DeviceMessage::RecoveryProbe(probe) if peer == joining.device().moss_peer_id => {
                Some(probe)
            }
            _ => None,
        })
        .expect("request original evidence from the surviving newly admitted installation");
    finish_new_relay_recovery(&mut f, &joining, &mut crypto, probe, addition, removal);
}

fn finish_new_relay_recovery(
    f: &mut Fixture,
    joining: &DeviceIdentity,
    crypto: &mut MlsSessionCrypto,
    probe: RecoveryProbe,
    addition: EpochRecord,
    removal: RemovalRecord,
) {
    let round = probe.round;
    let offer = f.packet(
        joining,
        DeviceMessage::RecoveryOffer(RecoveryOffer {
            probe,
            epoch: 3,
            manifest: "ab".repeat(32),
        }),
    );
    f.receive(&offer)
        .expect("accept an epoch-only offer from the signed roster candidate");
    let request_id = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .recovery
        .as_ref()
        .unwrap()
        .source
        .as_ref()
        .unwrap()
        .import
        .request_id
        .clone();
    let store = f.runtime.sessions.persistence().cloned().unwrap();
    let session = f.runtime.session_mut(&f.session).unwrap();
    assert!(
        session
            .recovery_packets(&store, now_ms())
            .unwrap()
            .iter()
            .any(|(peer, _)| peer == &joining.device().moss_peer_id),
        "pull missing commits from the not-yet-replayed client"
    );
    let mut batch = f.batch(0, vec![record("surviving-copy", "after recovery")]);
    batch.request_id = request_id.clone();
    batch.total = 1;
    batch.epoch = Some(3);
    let text = f.packet(
        joining,
        DeviceMessage::RecoveryBatch(
            crate::private_dm_runtime::devices::recovery::RecoveryBatch { round, batch },
        ),
    );
    assert!(
        f.receive(&text).is_err(),
        "roster permission for commit relay grants no text membership"
    );
    let add = f.packet(
        joining,
        DeviceMessage::RecoveryEpoch(RecoveryEpoch {
            round,
            request_id: request_id.clone(),
            evidence: addition,
        }),
    );
    f.receive(&add)
        .expect("verify original admitted author's Add before trusting the new MLS signer");
    let remove = f.packet(
        joining,
        DeviceMessage::RecoveryRemoval(RecoveryRemoval {
            round,
            request_id,
            evidence: removal,
        }),
    );
    let _ = f.receive(&remove);
    f.receive(&text)
        .expect("text membership follows verified Add and Remove");
    let session = f.runtime.session_mut(&f.session).unwrap();
    assert_eq!(session.crypto.member_count(), 2);
    let ciphertext = session.crypto.encrypt(b"surviving installation").unwrap();
    assert_eq!(
        crypto.decrypt(&ciphertext).unwrap(),
        b"surviving installation"
    );
}

pub(super) fn two_client_contact_recovers_missed_add_and_remove() {
    let mut f = Fixture::with_clients(false);
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(1)
    );
    let admission = recovery::next_admission(&mut f, "missed-first-add.redb", "first-add");
    let addition = EpochRecord::create(&f.contact, &admission, now_ms()).unwrap();
    let roster = f
        .contact
        .roster()
        .revoke(&admission.request.claim.device_id, &f.contact.key())
        .unwrap();
    let author = f.peers.get_mut(&f.contact.device().device_id).unwrap();
    let commit = author
        .remove_member_by_signer(&admission.request.claim.mls_signer)
        .unwrap();
    let removal = RemovalRecord::create(
        &f.contact,
        &f.session,
        admission.request.claim.device_id,
        roster.clone(),
        author,
        commit,
    )
    .unwrap();
    adopt(&mut f.contact, roster);
    let mut forged = removal.clone();
    forged.epoch += 1;
    let forged = f.packet(&f.contact, DeviceMessage::Removal(forged));
    assert!(f.receive(&forged).is_err());
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .recovery
        .is_none());
    let packet = f.packet(&f.contact, DeviceMessage::Removal(removal.clone()));
    assert!(
        f.receive(&packet).is_err(),
        "ahead evidence cannot install a skipped epoch"
    );
    f.runtime.rehydrate();
    let recovery = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .recovery
        .as_ref()
        .expect("authenticated ahead Remove must durably bootstrap two-client recovery");
    assert_eq!(recovery.required_epoch, 3);
    assert_eq!(
        f.runtime.session_ref(&f.session).unwrap().crypto.epoch(),
        Some(1)
    );
    let store = f.runtime.sessions.persistence().cloned().unwrap();
    let packets = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .recovery_packets(&store, now_ms() + 5_001)
        .unwrap();
    let probe = packets
        .into_iter()
        .find_map(|(_, message)| match message {
            DeviceMessage::RecoveryProbe(probe) => Some(probe),
            _ => None,
        })
        .expect("the original two-client membership must request its missed epochs");
    finish_ordered_recovery(&mut f, probe, addition, removal);
}

fn finish_ordered_recovery(
    f: &mut Fixture,
    probe: RecoveryProbe,
    addition: EpochRecord,
    removal: RemovalRecord,
) {
    let round = probe.round;
    let packet = f.packet(
        &f.contact,
        DeviceMessage::RecoveryOffer(RecoveryOffer {
            probe,
            epoch: 3,
            manifest: "ab".repeat(32),
        }),
    );
    f.receive(&packet).unwrap();
    let request_id = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .recovery
        .as_ref()
        .unwrap()
        .source
        .as_ref()
        .unwrap()
        .import
        .request_id
        .clone();
    let add = f.packet(
        &f.contact,
        DeviceMessage::RecoveryEpoch(RecoveryEpoch {
            round,
            request_id: request_id.clone(),
            evidence: addition,
        }),
    );
    f.receive(&add)
        .expect("recover the first missed Add before its Remove");
    let remove = f.packet(
        &f.contact,
        DeviceMessage::RecoveryRemoval(RecoveryRemoval {
            round,
            request_id,
            evidence: removal,
        }),
    );
    let _ = f.receive(&remove); // The durable transition precedes its disconnected acknowledgement.
    let session = f.runtime.session_mut(&f.session).unwrap();
    assert_eq!(session.crypto.epoch(), Some(3));
    assert_eq!(session.crypto.member_count(), 2);
    assert!(!session.awaiting_device_epoch());
    let ciphertext = session.crypto.encrypt(b"surviving contact").unwrap();
    assert_eq!(
        f.peers
            .get_mut(&f.contact.device().device_id)
            .unwrap()
            .decrypt(&ciphertext)
            .unwrap(),
        b"surviving contact"
    );
}
