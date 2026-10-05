use super::*;
use crate::sender_auth::SenderProof;

fn peer_id(seed: u8) -> String {
    hex::encode(
        SigningKey::from_bytes(&[seed; 32])
            .verifying_key()
            .to_bytes(),
    )
}

fn text(view: &mut MemberView) -> DataEnvelope {
    DataEnvelope {
        origin: None,
        group_id: view.group_id.clone(),
        participant_id: "cleo-participant".into(),
        from_device: "cleo".into(),
        from_fingerprint: peer_id(6),
        message_id: Some("authenticated-text".into()),
        sent_at_ms: Some(42),
        ciphertext_b64: encode(&view.cleo.encrypt(b"legitimate text").unwrap()),
    }
}

fn deliver_text(view: &mut MemberView, payload: Vec<u8>) -> Result<(), PrivateGroupError> {
    view.runtime
        .groups
        .get_mut(&view.group_id)
        .unwrap()
        .handle_data(payload)
}

fn tamper(payload: &[u8], field: &str, replacement: serde_json::Value) -> Vec<u8> {
    let mut proof: serde_json::Value = serde_json::from_slice(payload).unwrap();
    let bound_bytes = decode(proof["identity"]["payload_b64"].as_str().unwrap()).unwrap();
    let mut bound: serde_json::Value = serde_json::from_slice(&bound_bytes).unwrap();
    let data_bytes = decode(bound["payload_b64"].as_str().unwrap()).unwrap();
    let mut data: serde_json::Value = serde_json::from_slice(&data_bytes).unwrap();
    data[field] = replacement;
    bound["payload_b64"] = serde_json::json!(encode(&serde_json::to_vec(&data).unwrap()));
    proof["identity"]["payload_b64"] =
        serde_json::json!(encode(&serde_json::to_vec(&bound).unwrap()));
    serde_json::to_vec(&proof).unwrap()
}

#[test]
fn changed_signed_headers_are_rejected_before_consuming_the_genuine_text() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let envelope = text(&mut view);
    let payload = view.cleo_application(&envelope, &view.session().data_channel);
    for (field, replacement) in [
        ("from_device", serde_json::json!("dane")),
        ("from_fingerprint", serde_json::json!(peer_id(5))),
        ("message_id", serde_json::json!("changed")),
        ("sent_at_ms", serde_json::json!(43)),
        ("participant_id", serde_json::json!("changed")),
        ("group_id", serde_json::json!("changed")),
        ("ciphertext_b64", serde_json::json!(encode(b"changed"))),
    ] {
        assert!(
            deliver_text(&mut view, tamper(&payload, field, replacement)).is_err(),
            "{field}"
        );
        assert!(view.session().messages.is_empty());
    }
    deliver_text(&mut view, payload).unwrap();
    let snapshot = view.runtime.poll(&view.group_id).unwrap();
    assert_eq!(snapshot.messages[0].from_fingerprint, peer_id(6));
    assert_eq!(snapshot.messages[0].body, "legitimate text");
    assert_eq!(
        snapshot.messages[0].message_id.as_deref(),
        Some("authenticated-text")
    );
    assert_eq!(snapshot.messages[0].sent_at_ms, Some(42));
}

#[test]
fn a_members_proof_cannot_relabel_another_leafs_ciphertext_or_consume_its_ratchet() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let mut envelope = text(&mut view);
    let genuine = view.cleo_application(&envelope, &view.session().data_channel);
    envelope.from_fingerprint = peer_id(5);
    envelope.from_device = "dane".into();
    let proof = SenderProof::sign(
        &SigningKey::from_bytes(&[5; 32]),
        &view.dane,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &view.session().mesh_id,
            channel_kind: &view.session().data_channel,
        },
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    let before = view.session().crypto.snapshot();
    assert!(deliver_text(&mut view, serde_json::to_vec(&proof).unwrap()).is_err());
    assert_eq!(view.session().crypto.snapshot(), before);
    deliver_text(&mut view, genuine).unwrap();
    assert_eq!(
        view.runtime.poll(&view.group_id).unwrap().messages[0].from_fingerprint,
        peer_id(6)
    );
}

#[test]
fn even_a_valid_member_proof_must_name_its_actual_moss_identity() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let mut envelope = text(&mut view);
    envelope.from_fingerprint = peer_id(5);
    let payload = view.cleo_application(&envelope, &view.session().data_channel);
    assert!(deliver_text(&mut view, payload).is_err());
    assert!(view
        .runtime
        .poll(&view.group_id)
        .unwrap()
        .messages
        .is_empty());
}

#[test]
fn a_self_signed_outsider_cannot_reuse_member_ciphertext() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let mut envelope = text(&mut view);
    envelope.from_fingerprint = peer_id(7);
    let outsider = MlsSessionCrypto::new("outsider").unwrap();
    let proof = SenderProof::sign(
        &SigningKey::from_bytes(&[7; 32]),
        &outsider,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &view.session().mesh_id,
            channel_kind: &view.session().data_channel,
        },
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    assert!(deliver_text(&mut view, serde_json::to_vec(&proof).unwrap()).is_err());
    assert!(view
        .runtime
        .poll(&view.group_id)
        .unwrap()
        .messages
        .is_empty());
}

#[test]
fn proofs_do_not_cross_channels_or_pre_welcome_membership() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let envelope = text(&mut view);
    let payload = view.cleo_application(&envelope, &view.session().data_channel);
    let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
    assert!(session.handle_control(payload.clone(), None).is_err());
    session.joined = false;
    assert!(session.handle_data(payload.clone()).is_err());
    session.joined = true;
    session.handle_data(payload).unwrap();
}

#[test]
fn signed_malformed_typing_and_signed_membership_frames_are_rejected() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let envelope = ControlEnvelope::TypingIndicator {
        group_id: view.group_id.clone(),
        from_device: "cleo".into(),
        from_fingerprint: peer_id(6),
        typing_ciphertext_b64: encode(&view.cleo.encrypt(b"not JSON").unwrap()),
    };
    let payload = view.cleo_application(&envelope, &view.control_channel);
    assert!(view
        .runtime
        .groups
        .get_mut(&view.group_id)
        .unwrap()
        .handle_control(payload, None)
        .is_err());
    assert!(view
        .runtime
        .poll(&view.group_id)
        .unwrap()
        .typing_members
        .is_empty());
    let envelope = ControlEnvelope::AdminHandoff {
        group_id: view.group_id.clone(),
        from_fingerprint: peer_id(6),
        next_admin_fingerprint: peer_id(6),
    };
    let payload = view.cleo_application(&envelope, &view.control_channel);
    assert!(view
        .runtime
        .groups
        .get_mut(&view.group_id)
        .unwrap()
        .handle_control(payload, None)
        .is_err());
}

fn owned_dm_invite(seed: u8, target: &str) -> String {
    let mut crypto = MlsSessionCrypto::new("DM owner").unwrap();
    crypto.create_group().unwrap();
    let uri = format!(
        "mosh://invite?mesh=dm-mesh&session=dm-session&target={target}&moss={}#fp={}",
        peer_id(seed),
        crypto.fingerprint()
    );
    crate::private_dm_runtime::invite_ownership::sign_invite(
        &uri,
        &SigningKey::from_bytes(&[seed; 32]),
        &crypto,
    )
    .unwrap()
}

fn deliver_offer(view: &mut MemberView, invite_uri: String) -> Result<(), PrivateGroupError> {
    let offer = DmOffers::mint(
        "cleo".into(),
        peer_id(6),
        view.session().device_fingerprint.clone(),
        invite_uri,
    );
    let envelope = ControlEnvelope::DmOffer {
        group_id: view.group_id.clone(),
        offer_ciphertext_b64: view.cleo.encrypt_json(&offer).unwrap(),
    };
    let payload = view.cleo_application(&envelope, &view.control_channel);
    view.runtime
        .groups
        .get_mut(&view.group_id)
        .unwrap()
        .handle_control(payload, None)
}

#[test]
fn an_authenticated_member_can_offer_only_a_dm_owned_by_the_same_installation() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut view = MemberView::open(0);
    let target = view.session().device_fingerprint.clone();
    assert!(deliver_offer(&mut view, owned_dm_invite(5, &target)).is_err());
    assert!(deliver_offer(
        &mut view,
        "mosh://invite?mesh=m&session=s#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".into()
    )
    .is_err());
    let genuine = owned_dm_invite(6, &target);
    let changed = genuine.replace(&peer_id(6), &peer_id(5));
    assert!(deliver_offer(&mut view, changed).is_err());
    assert!(view
        .runtime
        .poll(&view.group_id)
        .unwrap()
        .dm_offers
        .is_empty());
    deliver_offer(&mut view, genuine.clone()).unwrap();
    deliver_offer(&mut view, genuine.clone()).unwrap();
    let offers = view.runtime.poll(&view.group_id).unwrap().dm_offers;
    assert_eq!(offers.len(), 1);
    assert_eq!(offers[0].from_fingerprint, peer_id(6));
    assert_eq!(offers[0].invite_uri, genuine);
}
