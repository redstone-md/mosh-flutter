use super::*;
use crate::message_deletion::DeleteScope;

#[test]
fn deleting_a_queued_text_cancels_delivery_after_restart() {
    let mut pair = Pair::new("delete-queued");
    pair.net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    let sent = pair
        .alice
        .send_message(&pair.session_id, "never publish me".into())
        .unwrap();
    pair.alice
        .delete_messages(
            &pair.session_id,
            std::slice::from_ref(&sent.message_id),
            DeleteScope::ForMe,
        )
        .unwrap();
    assert!(pair
        .alice
        .poll_session(&pair.session_id)
        .unwrap()
        .messages
        .is_empty());
    pair.restart_alice();
    pair.net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    for _ in 0..4 {
        pair.alice.poll_session(&pair.session_id).unwrap();
        pair.bob.poll_session(&pair.session_id).unwrap();
    }
    assert!(pair
        .alice
        .poll_session(&pair.session_id)
        .unwrap()
        .messages
        .is_empty());
    pair.assert_bob_received_nothing();
}

#[test]
fn global_deletion_waits_for_the_counterparts_saved_acknowledgement() {
    let mut pair = Pair::new("global-deletion");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "remove everywhere".into())
        .unwrap();
    pair.bob.poll_session(&pair.session_id).unwrap();
    pair.alice
        .delete_messages(
            &pair.session_id,
            std::slice::from_ref(&sent.message_id),
            DeleteScope::ForEveryone,
        )
        .unwrap();
    let own = pair.alice.poll_session(&pair.session_id).unwrap();
    assert!(own.messages[0].body.is_empty());
    assert_eq!(
        own.messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status,
        crate::message_deletion::DeletionStatus::Pending
    );
    for _ in 0..4 {
        pair.bob.poll_session(&pair.session_id).unwrap();
        pair.alice.poll_session(&pair.session_id).unwrap();
    }
    let peer = pair.bob.poll_session(&pair.session_id).unwrap();
    assert!(peer.messages[0].body.is_empty());
    assert_eq!(
        pair.alice.poll_session(&pair.session_id).unwrap().messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status,
        crate::message_deletion::DeletionStatus::Confirmed
    );
    pair.restart_alice();
    assert!(
        pair.alice.poll_session(&pair.session_id).unwrap().messages[0]
            .body
            .is_empty()
    );
}

#[test]
fn mixed_or_missing_bulk_targets_leave_the_entire_selection_unchanged() {
    let mut pair = Pair::new("delete-bulk-atomic");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "keep me".into())
        .unwrap();
    let result = pair.alice.delete_messages(
        &pair.session_id,
        &[sent.message_id, "missing".into()],
        DeleteScope::ForMe,
    );
    assert!(result.is_err());
    assert_eq!(
        pair.alice.poll_session(&pair.session_id).unwrap().messages[0].body,
        "keep me"
    );
}

#[test]
fn a_counterpart_cannot_delete_somebody_elses_text_for_everyone() {
    let mut pair = Pair::new("delete-wrong-author");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "only Alice may delete this".into())
        .unwrap();
    pair.bob.poll_session(&pair.session_id).unwrap();
    assert!(pair
        .bob
        .delete_messages(
            &pair.session_id,
            &[sent.message_id],
            DeleteScope::ForEveryone
        )
        .is_err());
    assert_eq!(
        pair.bob.poll_session(&pair.session_id).unwrap().messages[0].body,
        "only Alice may delete this"
    );
}

#[test]
fn hiding_an_already_published_send_does_not_cancel_its_delivery_buffer() {
    let mut pair = Pair::new("delete-sent-local");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "deliver despite hiding".into())
        .unwrap();
    pair.net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    pair.alice
        .delete_messages(&pair.session_id, &[sent.message_id], DeleteScope::ForMe)
        .unwrap();
    pair.restart_alice();
    pair.net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    for _ in 0..4 {
        pair.bob.poll_session(&pair.session_id).unwrap();
        pair.alice.poll_session(&pair.session_id).unwrap();
    }
    assert_eq!(
        pair.bob.poll_session(&pair.session_id).unwrap().messages[0].body,
        "deliver despite hiding"
    );
    assert!(pair
        .alice
        .poll_session(&pair.session_id)
        .unwrap()
        .messages
        .is_empty());
}

#[test]
fn a_late_history_write_cannot_restore_an_erased_row() {
    let mut pair = Pair::new("delete-history-replay");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "erase this stored body".into())
        .unwrap();
    let row = pair
        .store
        .list_messages(&pair.session_id)
        .unwrap()
        .pop()
        .unwrap();
    let stored: crate::conversation::history::StoredMessage<ChatMessage> =
        serde_json::from_slice(&row).unwrap();
    pair.alice
        .delete_messages(
            &pair.session_id,
            std::slice::from_ref(&sent.message_id),
            DeleteScope::ForMe,
        )
        .unwrap();
    pair.store
        .append_message(&pair.session_id, stored.sent_at_ms, &sent.message_id, &row)
        .unwrap();
    let rows = pair.store.list_messages(&pair.session_id).unwrap();
    let stored: crate::conversation::history::StoredMessage<ChatMessage> =
        serde_json::from_slice(&rows[0]).unwrap();
    assert!(stored.message.body.is_empty());
    pair.restart_alice();
    assert!(pair
        .alice
        .poll_session(&pair.session_id)
        .unwrap()
        .messages
        .is_empty());
}
