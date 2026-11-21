use super::protocol::GroupBody;
use super::*;
use crate::conversation::recovery::wire::HistoryMessage;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::history::{member, unsigned_text};
use crate::private_group_runtime::durability_tests::Fixture;

// MOSH-116: one stored text without an origin failed every history round,
// once per service turn.
#[test]
fn an_unsigned_text_from_an_older_client_does_not_stall_history_sync() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut sender, identity) = member(&mut fixture);
    inbox::deliver(unsigned_text(
        &fixture,
        &mut sender,
        &identity,
        "unsigned",
        "sent before origins",
    ));
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().messages.len(), 1);
    fixture.restart();

    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    session.sync_history(now_ms()).unwrap();
    assert!(session.recovery.occurrences_ready);
}

#[test]
fn a_history_round_that_fails_waits_for_the_next_probe() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.runtime.send(&fixture.id, "held".into()).unwrap();
    fixture.restart();
    let _refused = fixture.store.refuse_message_writes(GROUP_HISTORY);

    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let now = now_ms();
    assert!(session.sync_history(now).is_err());
    assert!(session.sync_history(now + 1000).is_ok());
}

// MOSH-116: Moss hands this device's own room probes back to it.
#[test]
fn an_echo_of_our_own_probe_is_not_a_bad_frame() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let body = GroupBody {
        scope: session.own_history_scope().unwrap(),
        message: HistoryMessage::Probe,
        evidence: None,
        partial_digest: None,
        erased_fragment: false,
    };
    let probe = session
        .history_envelope(None, "ab".repeat(16), 1, &body)
        .unwrap();
    let echo = session
        .sign_application(&probe, &session.control_channel)
        .unwrap();
    session.handle_authenticated_control(echo).unwrap();
}
