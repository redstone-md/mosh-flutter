//! A DM's unread count rides its poll and list, and viewing clears it.
use super::*;

#[test]
fn a_received_text_is_unread_until_the_dm_is_viewed() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let sent = alice
        .send_message(&invite.session_id, "hello".to_string())
        .expect("Alice should send");
    let unread = bob
        .poll_session(&invite.session_id)
        .expect("Bob poll should pass")
        .unread
        .expect("a poll carries the unread state");
    assert_eq!(unread.count, 1);
    assert_eq!(unread.first_unread_message_id, Some(sent.message_id));
    let listed = bob.list_sessions().expect("Bob list should pass").sessions;
    assert_eq!(listed[0].unread.as_ref().map(|u| u.count), Some(1));

    bob.mark_viewed(&invite.session_id)
        .expect("view should pass");
    let after = bob.poll_session(&invite.session_id).unwrap().unread;
    assert_eq!(after.map(|u| u.count), Some(0));
    let own = alice.poll_session(&invite.session_id).unwrap().unread;
    assert_eq!(own.map(|u| u.count), Some(0), "an own text is never unread");
}
