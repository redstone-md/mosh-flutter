use super::*;
use crate::private_dm_runtime::devices::recovery::{
    EpochRecord, Recovery, RecoveryBatch, RecoveryEpoch, RecoverySource,
};
use crate::private_dm_runtime::devices::types::{Admission, JoinRequest};
use crate::private_dm_runtime::ChatMessage;
use crate::private_dm_runtime::{contracts::DmHistorySyncState, now_ms};

mod historical;

pub(super) fn begin(f: &mut Fixture, source: &DeviceDescriptor, epoch: u64) {
    let session = f.runtime.session_mut(&f.session).unwrap();
    let membership = session.membership.as_mut().unwrap();
    membership.history_import.as_mut().unwrap().complete = true;
    membership.recovery = Some(Recovery {
        round: 7,
        request_id: "recovery-packets".into(),
        started_ms: now_ms(),
        last_rx_ms: now_ms(),
        required_epoch: epoch,
        source: Some(RecoverySource {
            device_id: source.device_id.clone(),
            epoch,
            import: HistoryImport::new("recovery-packets", source),
        }),
        observed: Default::default(),
    });
    session.record_dirty = true;
    f.runtime.sessions.persist_tail();
}

fn batch(f: &Fixture, offset: usize, total: usize, records: Vec<TextRecord>) -> RecoveryBatch {
    RecoveryBatch {
        round: 7,
        batch: HistoryBatch {
            session_id: f.session.clone(),
            epoch: None,
            request_id: "history-recovery-packets".into(),
            offset,
            total,
            manifest: "ab".repeat(32),
            records,
            fragment: None,
        },
    }
}

// Inspect packet results without ticking the fixed recovery round's timeout.
fn text(f: &Fixture, id: &str) -> Vec<ChatMessage> {
    f.runtime
        .session_ref(&f.session)
        .unwrap()
        .messages
        .iter()
        .filter(|message| message.message_id.as_deref() == Some(id))
        .cloned()
        .collect()
}

fn admitted_sources_and_prefix_rosters() {
    let mut f = Fixture::new();
    let mut listed = identity(&f.dir, "listed.redb");
    let roster = f
        .contact
        .roster()
        .extend(listed.device().clone(), &f.contact.key())
        .unwrap();
    adopt(&mut listed, roster.clone());
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .membership
        .as_mut()
        .unwrap()
        .topology
        .update_roster(roster)
        .unwrap();
    let source = f.contact.device().clone();
    begin(&mut f, &source, 2);
    let response = DeviceMessage::RecoveryBatch(batch(
        &f,
        0,
        1,
        vec![record("contact-copy", "Recovered from contact")],
    ));
    for sender in [&f.outsider, &listed, &f.receiver, &f.source] {
        let packet = f.packet(sender, response.clone());
        assert!(f.runtime.receive_device_packet(&packet).is_err());
    }
    let packet = f.packet(&f.contact, response);
    let mut tampered: serde_json::Value = serde_json::from_slice(&packet).unwrap();
    tampered["recipient"] = serde_json::Value::String("other recipient".into());
    assert!(f.receive(&serde_json::to_vec(&tampered).unwrap()).is_err());
    // The admitted contact's older valid roster can supply text. The newer
    // pinned roster still cannot give its listed, unadmitted device access.
    f.receive(&packet).unwrap();
    assert_eq!(text(&f, "contact-copy")[0].body, "Recovered from contact");
    assert!(f.receive(&packet).is_err());
    assert_eq!(text(&f, "contact-copy").len(), 1);
}

fn cursors_replays_and_conflicts() {
    let mut f = Fixture::new();
    let source = f.contact.device().clone();
    begin(&mut f, &source, 2);
    let session = f.runtime.session_mut(&f.session).unwrap();
    session.membership.as_mut().unwrap().history_import = None;
    session.record_dirty = true;
    f.runtime.sessions.persist_tail();
    let first = batch(&f, 0, 2, vec![record("first-copy", "First recovered text")]);
    let first_packet = f.packet(&f.contact, DeviceMessage::RecoveryBatch(first));
    f.receive(&first_packet).unwrap();
    assert!(f.receive(&first_packet).is_err());
    let mut earlier = record("second-copy", "Second recovered text");
    earlier.sent_at_ms = 41;
    let correct = batch(&f, 1, 2, vec![earlier]);
    let mut variants = vec![
        batch(&f, 1, 2, Vec::new()),
        batch(&f, 1, 2, vec![record("first-copy", "Conflicting text")]),
    ];
    let mut stale_round = correct.clone();
    stale_round.round = 6;
    variants.push(stale_round);
    let mut wrong_source_id = correct.clone();
    wrong_source_id.batch.request_id = "history-other".into();
    variants.push(wrong_source_id);
    let mut wrong_cursor = correct.clone();
    wrong_cursor.batch.offset = 20;
    variants.push(wrong_cursor);
    let mut changed_manifest = correct.clone();
    changed_manifest.batch.manifest = "cd".repeat(32);
    variants.push(changed_manifest);
    let mut changed_total = correct.clone();
    changed_total.batch.total = 3;
    variants.push(changed_total);
    for response in variants {
        let packet = f.packet(&f.contact, DeviceMessage::RecoveryBatch(response));
        assert!(f.receive(&packet).is_err());
        assert!(text(&f, "second-copy").is_empty());
    }
    let packet = f.packet(&f.contact, DeviceMessage::RecoveryBatch(correct));
    let pending = f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .membership
        .as_ref()
        .unwrap()
        .recovery
        .as_ref()
        .unwrap();
    assert_eq!(
        pending.round, 7,
        "invalid packets cannot replace the active recovery round"
    );
    f.receive(&packet).unwrap();
    assert_eq!(text(&f, "first-copy")[0].body, "First recovered text");
    assert_eq!(text(&f, "second-copy")[0].body, "Second recovered text");
    assert_eq!(
        f.snapshot().history_sync,
        Some(DmHistorySyncState::Complete)
    );
    let recovered: Vec<_> = f
        .snapshot()
        .messages
        .into_iter()
        .filter_map(|message| message.message_id)
        .filter(|id| id.ends_with("-copy"))
        .collect();
    assert_eq!(recovered, ["second-copy", "first-copy"]);
}

pub(super) fn next_admission(f: &mut Fixture, name: &str, token: &str) -> Admission {
    next_admission_with_lifetime(f, name, token, None)
}

fn next_admission_with_lifetime(
    f: &mut Fixture,
    name: &str,
    token: &str,
    lifetime: Option<openmls::prelude::Lifetime>,
) -> Admission {
    let mut joining = identity(&f.dir, name);
    let roster = f
        .contact
        .roster()
        .extend(joining.device().clone(), &f.contact.key())
        .unwrap();
    adopt(&mut f.contact, roster.clone());
    adopt(&mut joining, roster);
    let mut crypto = MlsSessionCrypto::new(&joining.device().device_id).unwrap();
    let request = JoinRequest {
        request_id: token.into(),
        claim: IdentityClaim::create(&joining, &f.session, &crypto.signer_public(), "Contact")
            .unwrap(),
        key_package: match lifetime {
            Some(lifetime) => crypto.key_package_with_lifetime(lifetime).unwrap(),
            None => crypto.key_package_bytes().unwrap(),
        },
    };
    let author = f.peers.get_mut(&f.contact.device().device_id).unwrap();
    let outcome = author.add_members(&[&request.key_package]).unwrap();
    let group_id = author.group_id_bytes().unwrap();
    let epoch = author.epoch().unwrap();
    for (device, peer) in &mut f.peers {
        if device != &f.contact.device().device_id {
            peer.process_commit(&outcome.commit_bytes).unwrap();
        }
    }
    Admission {
        request,
        commit: outcome.commit_bytes,
        welcome: outcome.welcome_bytes,
        tree: outcome.tree_bytes,
        topology: f
            .runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .topology
            .clone(),
        group_id,
        epoch,
        recovery_authorization: None,
    }
}

fn epoch_packet(f: &Fixture, evidence: EpochRecord) -> Vec<u8> {
    f.packet(
        &f.source,
        DeviceMessage::RecoveryEpoch(RecoveryEpoch {
            round: 7,
            request_id: "history-recovery-packets".into(),
            evidence,
        }),
    )
}

fn original_author_epoch_order_and_restart() {
    let mut f = Fixture::new();
    let third = next_admission(&mut f, "third.redb", "epoch-three");
    let first = EpochRecord::create(&f.contact, &third, now_ms()).unwrap();
    let fourth = next_admission(&mut f, "fourth.redb", "epoch-four");
    let second = EpochRecord::create(&f.contact, &fourth, now_ms()).unwrap();
    let source = f.source.device().clone();
    begin(&mut f, &source, 4);
    let future = epoch_packet(&f, second.clone());
    assert!(f.receive(&future).is_err());
    let mut tampered = first.clone();
    tampered.signature = "00".repeat(64);
    assert!(f.receive(&epoch_packet(&f, tampered)).is_err());
    let outsider = EpochRecord::create(&f.outsider, &third, now_ms()).unwrap();
    assert!(f.receive(&epoch_packet(&f, outsider)).is_err());
    let mut foreign = third.clone();
    foreign.group_id = vec![9];
    let foreign = EpochRecord::create(&f.contact, &foreign, now_ms()).unwrap();
    assert!(f.receive(&epoch_packet(&f, foreign)).is_err());
    let first_packet = epoch_packet(&f, first);
    f.receive(&first_packet).unwrap();
    assert_eq!(
        f.snapshot().history_sync,
        Some(DmHistorySyncState::WaitingForSource)
    );
    f.runtime.rehydrate();
    assert!(f.receive(&first_packet).is_err());
    f.receive(&future).unwrap();
    assert_eq!(
        f.snapshot().history_sync,
        Some(DmHistorySyncState::Importing)
    );
    let terminal = DeviceMessage::RecoveryBatch(batch(&f, 0, 0, Vec::new()));
    let terminal = f.packet(&f.source, terminal);
    f.receive(&terminal).unwrap();
    assert_eq!(
        f.snapshot().history_sync,
        Some(DmHistorySyncState::Complete)
    );
}

fn live_text_is_durable_before_observation_or_completion() {
    for equal_offer in [true, false] {
        let mut f = Fixture::new();
        let source = f.contact.device().clone();
        begin(&mut f, &source, 2);
        let live = record("live-before-tail", "Live text during recovery");
        let session = f.runtime.session_mut(&f.session).unwrap();
        // A live frame enters the log before tick writes its tail. Recovery
        // packets can arrive in that same drain, before the tail transaction.
        session.messages.push_stamped(live.clone().into_message());
        let message = if equal_offer {
            session
                .membership
                .as_mut()
                .unwrap()
                .recovery
                .as_mut()
                .unwrap()
                .source = None;
            DeviceMessage::RecoveryOffer(
                crate::private_dm_runtime::devices::recovery::RecoveryOffer {
                    probe: crate::private_dm_runtime::devices::recovery::RecoveryProbe {
                        session_id: f.session.clone(),
                        request_id: "recovery-packets".into(),
                        round: 7,
                    },
                    epoch: 2,
                    manifest: HistoryExport::freeze(
                        session,
                        &source,
                        &HistoryRequest {
                            session_id: f.session.clone(),
                            request_id: "history-recovery-packets".into(),
                            offset: 0,
                            body_offset: 0,
                        },
                    )
                    .unwrap()
                    .digest,
                },
            )
        } else {
            DeviceMessage::RecoveryBatch(batch(&f, 0, 1, vec![live]))
        };
        let packet = f.packet(&f.contact, message);
        f.receive(&packet).unwrap();
        f.runtime.rehydrate();
        assert_eq!(text(&f, "live-before-tail").len(), 1);
        assert_eq!(
            f.snapshot().history_sync,
            Some(DmHistorySyncState::Complete)
        );
    }
}

#[test]
fn signed_recovery_boundary_checks_admission_epochs_cursors_and_restart() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::devices::history::packet_tests::recovery::recovery_packet_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "isolated Moss keystore worker invoked by signed recovery test"]
fn recovery_packet_process() {
    admitted_sources_and_prefix_rosters();
    cursors_replays_and_conflicts();
    original_author_epoch_order_and_restart();
    live_text_is_durable_before_observation_or_completion();
}
