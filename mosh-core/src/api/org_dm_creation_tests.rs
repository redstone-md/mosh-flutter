use super::*;

fn send(fixture: &mut Fixture) -> Result<InviteCreated, ConversationBridgeError> {
    let target = crate::org_signing::peer_id_hex(&fixture.member);
    workflows::create_and_offer_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        &target,
        StartSessionRequest {
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
        },
    )
}

#[test]
fn publication_failure_discards_the_new_org_dm_invite() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let _publish = fail_next_test_publish("offer refused");
    assert_eq!(
        send(&mut fixture).unwrap_err().kind,
        ConversationBridgeErrorKind::Unavailable
    );
    assert!(fixture.dm.list_sessions().unwrap().sessions.is_empty());
    assert!(fixture.store.list_sessions().unwrap().is_empty());
    let invite = send(&mut fixture).unwrap();
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_links[0]
            .session_id
            .as_deref(),
        Some(invite.session_id.as_str())
    );
}

#[test]
fn post_publication_link_failure_keeps_the_offered_dm_durable() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = std::sync::Arc::new(std::sync::Mutex::new(None));
    let capture = fault.clone();
    let store = fixture.store.clone();
    let _publish = crate::moss_ffi::after_next_test_publish(move || {
        *capture.lock().unwrap() = Some(store.refuse_org_record_writes());
    });
    assert_eq!(
        send(&mut fixture).unwrap_err().kind,
        ConversationBridgeErrorKind::Persistence
    );
    let snapshot = fixture.dm.list_sessions().unwrap().sessions.remove(0);
    let signer = fixture
        .dm
        .session_signer_public(&snapshot.session_id)
        .unwrap();
    assert_eq!(fixture.store.list_sessions().unwrap().len(), 1);
    drop(fault.lock().unwrap().take());
    fixture.restart();
    assert_eq!(fixture.dm.list_sessions().unwrap().sessions.len(), 1);
    assert_eq!(
        fixture
            .dm
            .session_signer_public(&snapshot.session_id)
            .unwrap(),
        signer
    );
    let target = crate::org_signing::peer_id_hex(&fixture.member);
    fixture
        .org
        .link_dm(&fixture.org_key, &target, &snapshot.session_id)
        .unwrap();
}
