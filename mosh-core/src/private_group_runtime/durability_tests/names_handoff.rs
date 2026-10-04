use super::*;

fn departure(admin: &mut Fixture, member: &Fixture) -> MossReceivedMessage {
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    let envelope = ControlEnvelope::SelfRemove {
        group_id: admin.id.clone(),
        from_fingerprint: session.crypto.fingerprint(),
        proposal_b64: encode(&session.crypto.leave_proposal_bytes().unwrap()),
        name_state_proof_b64: session.name_handoff_proof().unwrap(),
    };
    MossReceivedMessage {
        channel: member
            .runtime
            .groups
            .get(&member.id)
            .unwrap()
            .control_channel
            .clone(),
        payload: serde_json::to_vec(&envelope).unwrap(),
    }
}

#[test]
fn refused_handoff_keeps_the_admin_until_the_name_is_saved_and_retried() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = super::names::admitted_pair();
    admin
        .runtime
        .rename_group(&admin.id, "After departure")
        .unwrap();
    let message = departure(&mut admin, &member);
    let refused = member.store.refuse_message_writes(GROUP_HISTORY);
    let session = member.runtime.groups.get_mut(&member.id).unwrap();
    let epoch = session.crypto.epoch();
    assert!(matches!(
        session.handle_moss_message(message.clone()),
        Err(PrivateGroupError::Persistence(_))
    ));
    assert_eq!(session.crypto.epoch(), epoch);
    assert_eq!(session.snapshot().member_count, 2);
    assert!(!session.snapshot().is_admin);
    drop(refused);
    member.restart();
    inbox::deliver(message);
    let successor = member.runtime.poll(&member.id).unwrap();
    assert_eq!(successor.member_count, 1);
    assert!(successor.is_admin);
    assert_eq!(successor.label.as_deref(), Some("After departure"));
    member.restart();
    assert_eq!(
        member.runtime.poll(&member.id).unwrap().label.as_deref(),
        Some("After departure")
    );
}

#[test]
fn malformed_optional_handoff_does_not_block_a_valid_departure() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = super::names::admitted_pair();
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    let envelope = ControlEnvelope::SelfRemove {
        group_id: admin.id.clone(),
        from_fingerprint: session.crypto.fingerprint(),
        proposal_b64: encode(&session.crypto.leave_proposal_bytes().unwrap()),
        name_state_proof_b64: Some("invalid-base64".into()),
    };
    inbox::deliver(MossReceivedMessage {
        channel: member
            .runtime
            .groups
            .get(&member.id)
            .unwrap()
            .control_channel
            .clone(),
        payload: serde_json::to_vec(&envelope).unwrap(),
    });
    let successor = member.runtime.poll(&member.id).unwrap();
    assert_eq!(successor.member_count, 1);
    assert!(successor.is_admin);
}
