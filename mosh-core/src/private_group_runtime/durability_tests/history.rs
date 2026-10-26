use super::*;
use crate::private_group_runtime::history::{native_acceptance_key, NativeAcceptance};

#[test]
fn snapshot_refusal_keeps_incoming_group_text_invisible_and_retryable() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut sender, identity) = member(&mut fixture);
    let first = text(
        &fixture,
        &mut sender,
        &identity,
        "first",
        "accepted after repair",
    );
    let repeated = MossReceivedMessage {
        channel: first.channel.clone(),
        payload: first.payload.clone(),
    };

    let refused = fixture.store.refuse_group_snapshot_writes();
    inbox::deliver(first);
    assert!(fixture
        .runtime
        .poll(&fixture.id)
        .unwrap()
        .messages
        .is_empty());
    assert!(fixture
        .store
        .group_history_evidence::<NativeAcceptance>(&native_acceptance_key(&fixture.id, "first"))
        .unwrap()
        .is_none());
    drop(refused);
    inbox::deliver(repeated);
    let accepted = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(accepted.messages.len(), 1);
    assert_eq!(accepted.messages[0].body, "accepted after repair");

    fixture.restart();
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().messages.len(), 1);
    let next = text(
        &fixture,
        &mut sender,
        &identity,
        "second",
        "live after restart",
    );
    inbox::deliver(next);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.messages.len(), 2);
    assert_eq!(snapshot.messages[1].body, "live after restart");
}

#[test]
fn native_acceptance_retains_the_exact_original_sender_proof_across_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut sender, identity) = member(&mut fixture);
    let frame = text(
        &fixture,
        &mut sender,
        &identity,
        "original",
        "portable authorship",
    );
    let original_proof = frame.payload.clone();
    inbox::deliver(frame);
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().messages.len(), 1);
    fixture.restart();
    let key = native_acceptance_key(&fixture.id, "original");
    let accepted: NativeAcceptance = fixture.store.group_history_evidence(&key).unwrap().unwrap();
    assert_eq!(accepted.original_sender_proof_b64, encode(&original_proof));
    assert_eq!(
        accepted.original_author_mls_key,
        hex::encode(sender.signer_public())
    );
    assert_eq!(
        accepted.original_author_moss_key,
        org_signing::peer_id_hex(&identity)
    );
    assert_eq!(accepted.context, sender.history_context().unwrap());
    verify_native_checkpoint(&fixture, &accepted, &original_proof);
    let saved = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(
        saved.messages[0].metadata.as_ref().unwrap().origin,
        accepted.origin
    );
    let rows = fixture.store.list_group_messages(&fixture.id).unwrap();
    let row: crate::conversation::history::StoredMessage<GroupMessage> =
        serde_json::from_slice(&rows[0]).unwrap();
    assert!(
        row.history_evidence.as_ref().unwrap().group.is_some(),
        "portable acceptance signatures must be retained with native provenance"
    );
    verify_portable_receipt(&fixture, &row);
}

#[test]
fn an_unsigned_welcome_commit_hint_cannot_blackhole_a_later_verified_commit() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let mut admin = MlsSessionCrypto::new("Alice").unwrap();
    admin.create_group().unwrap();
    let invite = build_invite_uri("hint-mesh", "hint-group", &admin.fingerprint(), &None);
    fixture.join(&invite, "Bob");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let package = session.pending_join_package.as_ref().unwrap();
    let admission = admin.add_members(&[package]).unwrap();
    let mut carol = MlsSessionCrypto::new("Carol").unwrap();
    let later = admin
        .add_members(&[&carol.key_package_bytes().unwrap()])
        .unwrap();
    let welcome = ControlEnvelope::Welcome {
        group_id: fixture.id.clone(),
        for_participant_id: session.participant_id.clone(),
        from_fingerprint: admin.fingerprint(),
        welcome_b64: encode(&admission.welcome_bytes),
        tree_b64: encode(&admission.tree_bytes),
        // This outer hint is unsigned; it need not be the admission commit.
        commit_b64: encode(&later.commit_bytes),
    };
    inbox::deliver(MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: serde_json::to_vec(&welcome).unwrap(),
    });
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 2);
    let control = fixture
        .runtime
        .groups
        .get(&fixture.id)
        .unwrap()
        .control_channel
        .clone();
    inbox::deliver(MossReceivedMessage {
        channel: control,
        payload: serde_json::to_vec(&ControlEnvelope::Commit {
            group_id: fixture.id.clone(),
            from_fingerprint: admin.fingerprint(),
            commit_b64: encode(&later.commit_bytes),
            roster_version: None,
        })
        .unwrap(),
    });
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 3);
}

fn member(fixture: &mut Fixture) -> (MlsSessionCrypto, SigningKey) {
    let mut sender = MlsSessionCrypto::new("Bob").unwrap();
    let package = sender.key_package_bytes().unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let admitted = session.crypto.add_members(&[&package]).unwrap();
    sender
        .join_welcome(&admitted.welcome_bytes, &admitted.tree_bytes)
        .unwrap();
    session.write_extra(&fixture.store).unwrap();
    (sender, SigningKey::from_bytes(&[83; 32]))
}

fn text(
    fixture: &Fixture,
    sender: &mut MlsSessionCrypto,
    identity: &SigningKey,
    id: &str,
    body: &str,
) -> MossReceivedMessage {
    let session = fixture.runtime.groups.get(&fixture.id).unwrap();
    let peer = org_signing::peer_id_hex(identity);
    let origin = crate::message_deletion::MessageOrigin::sign_mls(
        &format!("group:{}", fixture.id),
        id,
        body.as_bytes(),
        sender,
        None,
        Some(&peer),
    )
    .unwrap();
    let envelope = DataEnvelope {
        origin: Some(origin),
        group_id: fixture.id.clone(),
        participant_id: "independent-bob".into(),
        from_device: "Bob".into(),
        from_fingerprint: peer,
        message_id: Some(id.into()),
        sent_at_ms: Some(now_ms()),
        ciphertext_b64: encode(&sender.encrypt(body.as_bytes()).unwrap()),
    };
    let proof = crate::sender_auth::SenderProof::sign(
        identity,
        sender,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: &session.data_channel,
        },
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    MossReceivedMessage {
        channel: session.data_channel.clone(),
        payload: serde_json::to_vec(&proof).unwrap(),
    }
}

fn verify_portable_receipt(
    fixture: &Fixture,
    row: &crate::conversation::history::StoredMessage<GroupMessage>,
) {
    use sha2::{Digest, Sha256};
    let reference = row
        .history_evidence
        .as_ref()
        .unwrap()
        .group
        .as_ref()
        .unwrap();
    let key = format!(
        "group/{}/evidence/acceptance/{}",
        hex::encode(Sha256::digest(fixture.id.as_bytes())),
        reference.acceptance_evidence_hash
    );
    let receipt: serde_json::Value = fixture.store.group_history_evidence(&key).unwrap().unwrap();
    let input = receipt_input(&receipt);
    for prefix in ["mls", "moss"] {
        crate::signature_verification::verify(
            receipt[format!("holder_{prefix}_key")].as_str().unwrap(),
            receipt[format!("{prefix}_signature")].as_str().unwrap(),
            &input,
        )
        .unwrap();
    }
    let mut changed = receipt;
    changed["record_hash"] = serde_json::Value::String("f".repeat(64));
    assert!(crate::signature_verification::verify(
        changed["holder_mls_key"].as_str().unwrap(),
        changed["mls_signature"].as_str().unwrap(),
        &receipt_input(&changed),
    )
    .is_err());
}

fn receipt_input(receipt: &serde_json::Value) -> Vec<u8> {
    let reference = receipt["author_admission_instance"]
        .as_object()
        .unwrap()
        .iter()
        .next()
        .unwrap();
    let mut input = b"mosh-history-acceptance-v1\0".to_vec();
    input.extend(
        serde_json::to_vec(&(
            &receipt["version"],
            &receipt["evidence_id"],
            &receipt["record_hash"],
            &receipt["original_origin_hash"],
            (
                &receipt["historical_context"]["epoch"],
                &receipt["historical_context"]["hash"],
            ),
            reference,
            &receipt["holder_mls_key"],
            &receipt["holder_moss_key"],
            (
                &receipt["accepted_head"]["epoch"],
                &receipt["accepted_head"]["hash"],
            ),
            &receipt["basis"],
            &receipt["first_evidence_hash"],
            &receipt["predecessor_hash"],
        ))
        .unwrap(),
    );
    input
}

fn verify_native_checkpoint(fixture: &Fixture, accepted: &NativeAcceptance, original_proof: &[u8]) {
    let reference =
        serde_json::to_value(accepted.author_admission_instance.as_ref().unwrap()).unwrap();
    let checkpoint_id = reference["verified_since_checkpoint_v1"]
        .as_str()
        .expect("a typed checkpoint cannot masquerade as an Add admission");
    use sha2::{Digest, Sha256};
    let checkpoint_key = format!(
        "group/{}/evidence/membership/{checkpoint_id}",
        hex::encode(Sha256::digest(fixture.id.as_bytes()))
    );
    let checkpoint: serde_json::Value = fixture
        .store
        .group_history_evidence(&checkpoint_key)
        .unwrap()
        .unwrap();
    assert_eq!(checkpoint["checkpoint"]["context"]["epoch"], 1);
    assert_eq!(
        checkpoint["original_binding_proof_b64"],
        encode(original_proof)
    );
}
