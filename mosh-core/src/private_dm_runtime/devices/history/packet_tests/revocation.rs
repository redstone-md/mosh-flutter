use super::*;
use crate::private_dm_runtime::devices::recovery::{EpochRecord, RecoveryEpoch, RecoveryRemoval};
use crate::private_dm_runtime::devices::revocation::RemovalRecord;
use crate::private_dm_runtime::now_ms;
mod forgery;
mod multiple;

fn ordered_add_then_remove() {
    let mut f = Fixture::new();
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
    let stale_admission = f.packet(&f.contact, DeviceMessage::Admission(addition));
    assert!(f.receive(&stale_admission).is_err());
    assert_eq!(f.runtime.session_ref(&f.session).unwrap().crypto.epoch(), Some(2),
        "a direct old admission must not install a removed leaf; ordered recovery alone may replay the historical Add");
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
            round: 7,
            request_id: "history-recovery-packets".into(),
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
    f.snapshot();
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
}
