use super::*;
use crate::message_deletion::{cipher, fragments, shared, DeleteScope, DeletionStatus};

fn send_text(sender: &mut Fixture, receiver: &mut Fixture, body: &str) -> String {
    let _deferred = sender.refuse_data_publication("capture text");
    let sent = sender.runtime.send(&sender.id, body.into()).unwrap();
    let bytes = sender
        .store
        .get_outbound_attempt("private_group", &sender.id, &sent.message_id)
        .unwrap()
        .unwrap();
    let attempt: OutboundAttemptRecord = serde_json::from_slice(&bytes).unwrap();
    let channel = receiver
        .runtime
        .groups
        .get(&receiver.id)
        .unwrap()
        .data_channel
        .clone();
    inbox::deliver(MossReceivedMessage {
        channel,
        payload: decode(&attempt.publish_payload_b64).unwrap(),
    });
    assert!(receiver
        .runtime
        .poll(&receiver.id)
        .unwrap()
        .messages
        .iter()
        .any(|m| m.body == body));
    sent.message_id
}

fn deliver_state(sender: &mut Fixture, receiver: &mut Fixture) {
    let session = sender.runtime.groups.get_mut(&sender.id).unwrap();
    let authority = session.deletion_authority().unwrap();
    let page = shared::page(&session.deletions, None, &authority);
    for message in fragments::split(&page).unwrap() {
        let frame =
            cipher::seal_mls(&session.deletions.context, &session.crypto, &message).unwrap();
        let envelope = ControlEnvelope::MessageDeletion {
            group_id: sender.id.clone(),
            frame,
        };
        let proof = session
            .sign_application(&envelope, &session.control_channel)
            .unwrap();
        let payload = serde_json::to_vec(&proof).unwrap();
        assert!(payload.len() < 64 * 1024);
        inbox::deliver(MossReceivedMessage {
            channel: session.control_channel.clone(),
            payload,
        });
    }
    receiver.runtime.poll(&receiver.id).unwrap();
}

#[test]
fn admin_moderation_is_authenticated_acknowledged_and_durable() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = names::admitted_pair();
    let id = send_text(&mut member, &mut admin, "member text");
    let original = admin.runtime.poll(&admin.id).unwrap();
    assert!(
        original.messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .can_delete_for_everyone
    );
    admin
        .runtime
        .delete_messages(&admin.id, &[id], DeleteScope::ForEveryone)
        .unwrap();
    let pending = admin.runtime.poll(&admin.id).unwrap();
    assert_eq!(pending.messages[0].body, "");
    assert_eq!(
        pending.messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .administrator
            .as_deref(),
        Some("Alice")
    );
    deliver_state(&mut admin, &mut member);
    assert_eq!(
        member.runtime.poll(&member.id).unwrap().messages[0].body,
        ""
    );
    deliver_state(&mut member, &mut admin);
    let confirmed = admin.runtime.poll(&admin.id).unwrap();
    assert_eq!(
        confirmed.messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status,
        DeletionStatus::Confirmed
    );
    admin.restart();
    member.restart();
    assert_eq!(admin.runtime.poll(&admin.id).unwrap().messages[0].body, "");
    assert_eq!(
        member.runtime.poll(&member.id).unwrap().messages[0].body,
        ""
    );
}

#[test]
fn ordinary_members_cannot_delete_another_authors_messages() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = names::admitted_pair();
    let id = send_text(&mut admin, &mut member, "admin text");
    assert!(member
        .runtime
        .delete_messages(&member.id, &[id], DeleteScope::ForEveryone)
        .is_err());
    assert_eq!(
        member.runtime.poll(&member.id).unwrap().messages[0].body,
        "admin text"
    );
}

#[test]
fn deleting_a_name_event_only_changes_personal_history() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let renamed = f.runtime.rename_group(&f.id, "Work").unwrap();
    let id = renamed.messages[0].message_id.clone().unwrap();
    assert!(f
        .runtime
        .delete_messages(&f.id, std::slice::from_ref(&id), DeleteScope::ForEveryone)
        .is_err());
    f.runtime
        .delete_messages(&f.id, &[id], DeleteScope::ForMe)
        .unwrap();
    f.restart();
    let snapshot = f.runtime.poll(&f.id).unwrap();
    assert!(snapshot.messages.is_empty());
    assert_eq!(snapshot.label.as_deref(), Some("Work"));
}
