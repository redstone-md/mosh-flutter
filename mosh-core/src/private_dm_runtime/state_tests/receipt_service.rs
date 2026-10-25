use super::*;

#[test]
fn disabled_view_does_not_service_saved_conversations() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    let net = MemoryNet::new();
    let mut alice = runtime_on(&net, ALICE_ID);
    let session = invite(&mut alice).session_id;
    for _ in 0..3 {
        invite(&mut alice);
    }
    for explicit_off in [false, true] {
        if explicit_off {
            alice.set_read_receipts_enabled(false).unwrap();
        }
        let before = net.mesh_reports(ALICE_ID);
        for _ in 0..10 {
            alice.mark_viewed(&session).unwrap();
        }
        assert_eq!(
            net.mesh_reports(ALICE_ID),
            before,
            "disabled receipt commands must not drive maintenance for saved chats"
        );
        alice.service();
        assert_eq!(net.mesh_reports(ALICE_ID), before + 1);
    }
    clear_toggle(&dir);
}

#[test]
fn enabled_view_receives_and_receipts_without_global_maintenance() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    let (net, mut alice, mut bob) = memory_pair();
    let invitation = invite(&mut alice);
    accept(&mut bob, &invitation);
    connect(&mut alice, &mut bob, &invitation.session_id);
    bob.set_read_receipts_enabled(true).unwrap();
    let sent = alice
        .send_message(
            &invitation.session_id,
            "Viewed through the receipt command".into(),
        )
        .unwrap();
    let before = net.mesh_reports(BOB_ID);
    bob.mark_viewed(&invitation.session_id).unwrap();
    assert_eq!(
        net.mesh_reports(BOB_ID),
        before,
        "an enabled receipt command receives the message without ticking every chat"
    );
    let snapshot = alice.poll_session(&invitation.session_id).unwrap();
    let message = snapshot
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(sent.message_id.as_str()))
        .unwrap();
    assert_eq!(message.read, Some(true));
    clear_toggle(&dir);
}
