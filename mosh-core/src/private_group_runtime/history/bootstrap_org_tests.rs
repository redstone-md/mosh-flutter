use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::Fixture;
use ed25519_dalek::SigningKey;

fn join(
    fixture: &mut Fixture,
    admin: &mut MlsSessionCrypto,
    issuer: &SigningKey,
    org: &str,
    invite: &str,
) {
    let _identity = crate::moss_ffi::replace_test_keystore(Some(fixture.store.clone()));
    fixture.id = fixture
        .runtime
        .join_group(JoinGroupRequest {
            invite_uri: invite.into(),
            display_name: "verified member".into(),
            org_pubkey: Some(org.into()),
            listen_port: 0,
            static_peer: None,
        })
        .unwrap()
        .group_id;
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let outcome = admin
        .add_members(&[session.pending_join_package.as_ref().unwrap()])
        .unwrap();
    let envelope = ControlEnvelope::Welcome {
        group_id: fixture.id.clone(),
        for_participant_id: session.participant_id.clone(),
        from_fingerprint: admin.fingerprint(),
        welcome_b64: encode(&outcome.welcome_bytes),
        tree_b64: encode(&outcome.tree_bytes),
        commit_b64: encode(&outcome.commit_bytes),
        admission_binding: None,
    };
    let payload = crate::private_group_runtime::wires::control_payload(
        &session.control_channel,
        &session.mesh_id,
        Some((org, issuer)),
        &envelope,
    )
    .unwrap();
    session
        .handle_moss_message(MossReceivedMessage {
            channel: session.control_channel.clone(),
            payload,
        })
        .unwrap();
    assert!(session.joined);
}

#[test]
fn a_restarted_org_joiner_retains_original_add_authority_and_refuses_changed_roles() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut receiver, mut holder) = (Fixture::new(), Fixture::new());
    let issuer = SigningKey::from_bytes(&[95; 32]);
    let root = SigningKey::from_bytes(&[96; 32]);
    let org = org_signing::peer_id_hex(&root);
    let issuer_id = org_signing::peer_id_hex(&issuer);
    let mut admin = MlsSessionCrypto::new(&issuer_id).unwrap();
    admin.create_group().unwrap();
    let peers: Vec<_> = [&receiver, &holder]
        .into_iter()
        .map(|fixture| {
            fixture
                .runtime
                .groups
                .get(&fixture.id)
                .unwrap()
                .device_fingerprint
                .clone()
        })
        .collect();
    let mut roster = serde_json::json!({"org_pubkey":org, "org_name":"Native history", "version":1,
        "members":[{"moss_peer_id":issuer_id,"name":"issuer","role":"admin"},
            {"moss_peer_id":peers[0],"name":"receiver","role":"member"},
            {"moss_peer_id":peers[1],"name":"holder","role":"member"}]});
    let roster_bytes = org_roster::sign_roster(&mut roster, &root).unwrap();
    for fixture in [&receiver, &holder] {
        fixture.store.put_org_roster(&org, &roster_bytes).unwrap();
    }
    let invite = build_invite_uri(
        "org-evidence",
        "org-evidence",
        &admin.fingerprint(),
        &Some(org.clone()),
    );
    join(&mut receiver, &mut admin, &issuer, &org, &invite);
    let prior = admin.history_context().unwrap();
    join(&mut holder, &mut admin, &issuer, &org, &invite);
    holder.restart();
    let source = holder.runtime.groups.get_mut(&holder.id).unwrap();
    let transition = source.retained_transition(&prior).unwrap();
    let target = source.current_history_head().unwrap();
    let bytes = serde_json::to_vec(&transition).unwrap();
    let session = receiver.runtime.groups.get_mut(&receiver.id).unwrap();
    assert_eq!(session.crypto.history_context().unwrap(), prior);
    let original = transition.original_signed_transition.as_ref().unwrap();
    let authority: serde_json::Value = decode_json(&decode(original).unwrap()).unwrap();
    for wrong_scope in [false, true] {
        let mut authority = authority.clone();
        if wrong_scope {
            authority["org"] = "97".repeat(32).into();
        } else {
            roster["members"][0]["role"] = "member".into();
            authority["roster"] =
                encode(&org_roster::sign_roster(&mut roster, &root).unwrap()).into();
        }
        let mut forged = serde_json::to_value(&transition).unwrap();
        forged["original_signed_transition"] =
            encode(&serde_json::to_vec(&authority).unwrap()).into();
        assert!(session
            .install_transition_evidence(
                &prior,
                &target,
                &serde_json::to_vec(&forged).unwrap(),
                "org-partial\u{1}state"
            )
            .is_err());
        assert_eq!(session.crypto.history_context().unwrap(), prior);
    }
    let fault = receiver.store.refuse_group_snapshot_writes();
    assert!(matches!(
        session.install_transition_evidence(&prior, &target, &bytes, "org-partial\u{1}state"),
        Err(PrivateGroupError::Persistence(_))
    ));
    assert_eq!(session.crypto.history_context().unwrap(), prior);
    drop(fault);
    session
        .install_transition_evidence(&prior, &target, &bytes, "org-partial\u{1}state")
        .unwrap();
    assert_eq!(session.crypto.member_count(), 3);
    assert_eq!(session.crypto.history_context().unwrap(), target.context);
}
