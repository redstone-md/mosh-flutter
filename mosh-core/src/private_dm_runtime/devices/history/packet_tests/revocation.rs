use super::*;
use crate::private_dm_runtime::devices::recovery::{EpochRecord, RecoveryEpoch, RecoveryRemoval};
use crate::private_dm_runtime::devices::revocation::RemovalRecord;
use crate::private_dm_runtime::now_ms;
use sha2::Digest;
mod forgery;
mod multiple;

fn ordered_add_then_remove() {
    let mut f = Fixture::new();
    let contact = f.peers.get(&f.contact.device().device_id).unwrap();
    let mut before_add = MlsSessionCrypto::restore(
        "Contact",
        &contact.signer_public(),
        &contact.snapshot(),
        &contact.group_id_bytes().unwrap(),
    )
    .unwrap();
    let addition = recovery::next_admission(&mut f, "removed.redb", "missed-add");
    let add = EpochRecord::create(&f.contact, &addition, now_ms()).unwrap();
    let target = addition.request.claim.device_id.clone();
    let roster = f
        .contact
        .roster()
        .revoke(&target, &f.contact.key())
        .unwrap();
    let author = f.peers.get_mut(&f.contact.device().device_id).unwrap();
    let mut before_remove = MlsSessionCrypto::restore(
        "Contact",
        &author.signer_public(),
        &author.snapshot(),
        &author.group_id_bytes().unwrap(),
    )
    .unwrap();
    let commit = author
        .remove_member_by_signer(&addition.request.claim.mls_signer)
        .unwrap();
    let removal = RemovalRecord::create(
        &f.contact,
        &f.session,
        target,
        roster.clone(),
        author,
        commit.clone(),
    )
    .unwrap();
    f.peers
        .get_mut(&f.source.device().device_id)
        .unwrap()
        .process_commit(&commit)
        .unwrap();
    adopt(&mut f.contact, roster);
    let claim = IdentityClaim::create(
        &f.contact,
        &f.session,
        &before_add.signer_public(),
        "Contact",
    )
    .unwrap();
    let ciphertext = before_add
        .encrypt(&serde_json::to_vec(&claim).unwrap())
        .unwrap();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .accept_identity_claim(&crate::private_dm_runtime::encode(&ciphertext))
        .unwrap();
    assert!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .pending_rosters
            .iter()
            .any(|r| r.user_id() == f.contact.roster().user_id()),
        "a future removal roster must stay separate from the old MLS topology"
    );
    let mut batch = f.batch(
        0,
        vec![
            record("future-first", "new epoch text"),
            record("future-second", "more new epoch text"),
        ],
    );
    batch.epoch = Some(4);
    let initial = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
    assert!(
        f.receive(&initial).is_err(),
        "initial history must first recover its signed source epoch"
    );
    let stale_admission = f.packet(&f.contact, DeviceMessage::Admission(addition));
    assert!(f.receive(&stale_admission).is_err());
    assert_eq!(f.runtime.session_ref(&f.session).unwrap().crypto.epoch(), Some(2),
        "a direct old admission must not install a removed leaf; ordered recovery alone may replay the historical Add");
    let (round, request_id) = start_initial_epoch_recovery(&mut f);
    let packet = f.packet(
        &f.source,
        DeviceMessage::RecoveryEpoch(RecoveryEpoch {
            round,
            request_id: request_id.clone(),
            evidence: add,
        }),
    );
    f.receive(&packet).expect("apply missed Add");
    // Linking and DM owners run independently. A signed roster can reach a
    // participant under the previous epoch before the Remove commit does.
    let claim = IdentityClaim::create(
        &f.contact,
        &f.session,
        &before_remove.signer_public(),
        "Contact",
    )
    .unwrap();
    let ciphertext = before_remove
        .encrypt(&serde_json::to_vec(&claim).unwrap())
        .unwrap();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .accept_identity_claim(&crate::private_dm_runtime::encode(&ciphertext))
        .unwrap();
    let packet = f.packet(
        &f.source,
        DeviceMessage::RecoveryRemoval(RecoveryRemoval {
            round,
            request_id,
            evidence: removal,
        }),
    );
    let _ = f.receive(&packet); // A real node with no connected peer cannot deliver an acknowledgement.
    let ciphertext = f
        .peers
        .get_mut(&f.source.device().device_id)
        .unwrap()
        .encrypt(b"protected")
        .unwrap();
    assert_eq!(
        f.runtime
            .session_mut(&f.session)
            .unwrap()
            .crypto
            .decrypt(&ciphertext)
            .unwrap(),
        b"protected"
    );
    f.receive(&initial)
        .expect("initial import resumes after ordered Add and Remove");
}

fn start_initial_epoch_recovery(f: &mut Fixture) -> (u64, String) {
    f.snapshot();
    let membership = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap();
    assert!(!membership.history_import.as_ref().unwrap().complete);
    let recovery = membership
        .recovery
        .as_ref()
        .expect("ordered recovery must run while initial import waits");
    let round = recovery.round;
    let request_id = recovery.request_id.clone();
    let offer = super::super::super::recovery::RecoveryOffer {
        probe: super::super::super::recovery::RecoveryProbe {
            session_id: f.session.clone(),
            round,
            request_id: request_id.clone(),
        },
        epoch: 4,
        manifest: "cd".repeat(32),
    };
    let packet = f.packet(&f.source, DeviceMessage::RecoveryOffer(offer));
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
    (round, request_id)
}

#[test]
fn signed_removal_boundary_recovers_ordered_evidence() {
    let status = std::process::Command::new(std::env::current_exe().unwrap()).args([
        "--exact", "private_dm_runtime::devices::history::packet_tests::revocation::revocation_packet_process",
        "--ignored", "--nocapture",
    ]).status().unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "isolated real Moss keystore worker"]
fn revocation_packet_process() {
    ordered_add_then_remove();
    fresh_roster_permission_does_not_revive_an_old_mls_leaf();
    forgery::original_author_exact_leaf_and_replay();
    multiple::signed_roster_order_preserves_the_remaining_client();
    initial_history_waits_for_an_observed_removal();
    removing_an_unadmitted_device_does_not_block_initial_history();
}

fn removing_an_unadmitted_device_does_not_block_initial_history() {
    let mut f = Fixture::new();
    let third = identity(&f.dir, "unadmitted.redb");
    let roster = f
        .receiver
        .roster()
        .extend(third.device().clone(), &f.receiver.key())
        .unwrap()
        .revoke(&third.device().device_id, &f.receiver.key())
        .unwrap();
    adopt(&mut f.receiver, roster.clone());
    adopt(&mut f.source, roster);
    f.snapshot();
    let mut batch = f.batch(
        0,
        vec![record("one", "current epoch"), record("two", "same epoch")],
    );
    batch.epoch = Some(2);
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
    f.receive(&packet)
        .expect("a device which never joined has no MLS transition to wait for");
}

fn initial_history_waits_for_an_observed_removal() {
    let mut f = Fixture::new();
    let (third, crypto) = multiple::admit_third(&mut f);
    let roster = f
        .receiver
        .roster()
        .revoke(&third.device().device_id, &f.source.key())
        .unwrap();
    adopt(&mut f.receiver, roster.clone());
    adopt(&mut f.source, roster.clone());
    f.snapshot();
    let batch = f.batch(
        0,
        vec![
            record("future-one", "after removal"),
            record("future-two", "after removal too"),
        ],
    );
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
    assert!(
        f.receive(&packet).is_err(),
        "initial import must wait for its known removal epoch"
    );
    let session = f.runtime.session_ref(&f.session).unwrap();
    assert_eq!(
        session
            .membership
            .as_ref()
            .unwrap()
            .history_import
            .as_ref()
            .unwrap()
            .cursor,
        0
    );
    assert!(
        session.membership.as_ref().unwrap().recovery.is_some(),
        "an incomplete initial import must still start ordered epoch recovery"
    );
    let source = f.peers.get_mut(&f.source.device().device_id).unwrap();
    let commit = source
        .remove_member_by_signer(&hex::encode(crypto.signer_public()))
        .unwrap();
    let evidence = RemovalRecord::create(
        &f.source,
        &f.session,
        third.device().device_id.clone(),
        roster,
        source,
        commit,
    )
    .unwrap();
    let removal = f.packet(&f.source, DeviceMessage::Removal(evidence));
    let _ = f.receive(&removal); // No connected peer can receive the durable-save acknowledgement.
    f.receive(&packet)
        .expect("the same correlated text can import after Remove");
    assert!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .history_import
            .as_ref()
            .unwrap()
            .complete
    );
}

fn fresh_roster_permission_does_not_revive_an_old_mls_leaf() {
    let mut f = Fixture::new();
    let roster = f
        .receiver
        .roster()
        .revoke(&f.source.device().device_id, &f.receiver.key())
        .unwrap()
        .extend(f.source.device().clone(), &f.receiver.key())
        .unwrap();
    adopt(&mut f.receiver, roster);
    assert_pending_removal(&f);
    f.snapshot();
    assert_pending_removal(&f);
    let ciphertext = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .crypto
        .encrypt(b"after removal and fresh permission")
        .unwrap();
    assert!(
        f.peers
            .get_mut(&f.source.device().device_id)
            .unwrap()
            .decrypt(&ciphertext)
            .is_err(),
        "fresh roster permission must require a new MLS join; the old leaf stays removed"
    );
    let evidence = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .removals
        .last()
        .unwrap()
        .evidence
        .clone();
    let packet = f.packet(
        &f.contact,
        DeviceMessage::RemovalAck {
            session_id: f.session.clone(),
            epoch: evidence.epoch,
            evidence: hex::encode(sha2::Sha256::digest(serde_json::to_vec(&evidence).unwrap())),
        },
    );
    f.receive(&packet).unwrap();
    assert!(f.receiver.revocations().unwrap().is_empty(),
        "fresh permission must stop showing the old removal once its remaining participant has acknowledged");
}

fn assert_pending_removal(f: &Fixture) {
    let statuses = f.receiver.revocations().unwrap();
    assert!(statuses.iter().any(|s| s.device.device_id == f.source.device().device_id
        && s.state == crate::device_link::types::DeviceRevocationState::Pending),
        "fresh roster permission must retain the removal status while the old leaf or its acknowledgement is pending");
}
