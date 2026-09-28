use super::*;
use crate::private_dm_runtime::devices::recovery::{RecoveryBatch, RecoveryPull};

pub(super) fn recovery_text_waits_for_known_remove() {
    let mut f = Fixture::new();
    let (third, crypto) = multiple::admit_third(&mut f);
    let source = f.source.device().clone();
    recovery::begin(&mut f, &source, 3);
    let roster = f
        .receiver
        .roster()
        .revoke(&third.device().device_id, &f.source.key())
        .unwrap();
    adopt(&mut f.receiver, roster.clone());
    adopt(&mut f.source, roster.clone());
    f.snapshot();
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .awaiting_device_epoch());
    let mut pull_request = RecoveryPull {
        round: 7,
        epoch: 3,
        request: HistoryRequest {
            session_id: f.session.clone(),
            request_id: "history-recovery-packets".into(),
            offset: 0,
            body_offset: 0,
        },
    };
    let pull = f.packet(&f.source, DeviceMessage::RecoveryPull(pull_request.clone()));
    let _ = f.receive(&pull); // The disconnected source cannot receive a response.
    assert!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .recovery_exports
            .is_empty(),
        "pending Remove must not freeze a text export at its old epoch"
    );
    let mut batch = f.batch(0, vec![record("blocked-recovery", "after roster removal")]);
    batch.request_id = "history-recovery-packets".into();
    batch.total = 1;
    batch.epoch = Some(3);
    let batch = f.packet(
        &f.source,
        DeviceMessage::RecoveryBatch(RecoveryBatch { round: 7, batch }),
    );
    assert!(
        f.receive(&batch).is_err(),
        "a selected old-epoch source cannot bypass known Remove"
    );
    assert_unchanged_import(&f);
    apply_remove(&mut f, &third, &crypto, roster);
    f.receive(&batch)
        .expect("recovery text resumes after the known Remove");
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .messages
        .iter()
        .any(|m| m.message_id.as_deref() == Some("blocked-recovery")));
    pull_request.epoch = 4;
    let pull = f.packet(&f.source, DeviceMessage::RecoveryPull(pull_request));
    let _ = f.receive(&pull);
    assert_eq!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .membership
            .as_ref()
            .unwrap()
            .recovery_exports
            .len(),
        1,
        "the same request may export text after Remove"
    );
}

fn assert_unchanged_import(f: &Fixture) {
    let session = f.runtime.session_ref(&f.session).unwrap();
    assert!(session
        .messages
        .iter()
        .all(|m| m.message_id.as_deref() != Some("blocked-recovery")));
    assert_eq!(
        session
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
            .cursor,
        0
    );
}

fn apply_remove(
    f: &mut Fixture,
    third: &DeviceIdentity,
    crypto: &MlsSessionCrypto,
    roster: DeviceRoster,
) {
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
    let packet = f.packet(&f.source, DeviceMessage::Removal(evidence));
    let _ = f.receive(&packet); // Durable installation precedes the disconnected acknowledgement.
    assert!(!f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .awaiting_device_epoch());
}

pub(super) fn higher_epoch_is_recorded_while_text_waits() {
    for recovery_import in [true, false] {
        let mut f = Fixture::new();
        let (third, _) = multiple::admit_third(&mut f);
        let source = f.source.device().clone();
        if recovery_import {
            recovery::begin(&mut f, &source, 3);
        }
        let roster = f
            .receiver
            .roster()
            .revoke(&third.device().device_id, &f.source.key())
            .unwrap();
        adopt(&mut f.receiver, roster.clone());
        adopt(&mut f.source, roster);
        f.snapshot();
        for epoch in [9, 10] {
            let mut batch = f.batch(0, vec![record("blocked-recovery", "future")]);
            batch.total = 1;
            batch.epoch = Some(epoch);
            let message = if recovery_import {
                batch.request_id = "history-recovery-packets".into();
                DeviceMessage::RecoveryBatch(RecoveryBatch { round: 7, batch })
            } else {
                DeviceMessage::HistoryBatch(batch)
            };
            let packet = f.packet(&f.source, message);
            assert!(f.receive(&packet).is_err());
            f.runtime.rehydrate();
            let session = f.runtime.session_ref(&f.session).unwrap();
            assert!(session
                .messages
                .iter()
                .all(|m| m.message_id.as_deref() != Some("blocked-recovery")));
            let membership = session.membership.as_ref().unwrap();
            let import = if recovery_import {
                &membership
                    .recovery
                    .as_ref()
                    .unwrap()
                    .source
                    .as_ref()
                    .unwrap()
                    .import
            } else {
                membership.history_import.as_ref().unwrap()
            };
            assert_eq!(import.cursor, 0);
            assert_eq!(
                membership.recovery.as_ref().unwrap().required_epoch,
                epoch,
                "every newer correlated epoch survives a restart while text remains paused"
            );
        }
    }
}
