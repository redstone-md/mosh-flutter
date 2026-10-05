use super::*;

#[test]
fn a_legacy_session_recovers_its_address_only_from_an_authenticated_hello() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut runtime, id) = lone_session(42185);
    let session = runtime.sessions.get_mut(&id).unwrap();
    let mut peer = MlsSessionCrypto::new("Bob").unwrap();
    let (welcome, tree) = session
        .crypto
        .add_peer(&peer.key_package_bytes().unwrap())
        .unwrap();
    peer.join_welcome(&welcome, &tree).unwrap();
    session.peer_joined = true;
    session.peer_moss_id = None;
    session
        .handle_control(
            serde_json::to_vec(&ControlEnvelope::PeerAnnounce {
                session_id: id.clone(),
                participant_id: "bystander".into(),
                from_device: "Mallory".into(),
                moss_peer_id: "ab".repeat(32),
            })
            .unwrap(),
        )
        .unwrap();
    assert!(session.peer_moss_id.is_none());
    let address = "cd".repeat(32);
    session
        .handle_control(
            serde_json::to_vec(&ControlEnvelope::Hello {
                session_id: id,
                participant_id: "bob".into(),
                from_device: "Bob".into(),
                hello_ciphertext_b64: encode(&peer.encrypt(address.as_bytes()).unwrap()),
            })
            .unwrap(),
        )
        .unwrap();
    assert_eq!(session.peer_moss_id.as_deref(), Some(address.as_str()));
    assert!(session.record_dirty);
}
