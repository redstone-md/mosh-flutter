use super::*;
use crate::private_group_runtime::history::{native_acceptance_key, NativeAcceptance};

#[test]
fn refused_snapshot_preserves_the_exact_original_attachment_offer_for_retry() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut sender, identity) = super::history::member(&mut fixture);
    let frame = attachment(&fixture, &mut sender, &identity);
    let fault = fixture.store.refuse_group_snapshot_writes();
    inbox::deliver(frame.clone());
    let refused = fixture.runtime.poll(&fixture.id).unwrap();
    assert!(refused.messages.is_empty());
    assert!(refused.attachments.is_empty());
    drop(fault);
    inbox::deliver(frame);
    let accepted = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(accepted.messages.len(), 1);
    assert_eq!(accepted.messages[0].sent_at_ms, Some(42));
    assert_eq!(
        accepted.attachments[0].state,
        crate::conversation::attachments::AttachmentState::Offered
    );
    let evidence: NativeAcceptance = fixture
        .store
        .group_history_evidence(&native_acceptance_key(&fixture.id, "recoverable-offer"))
        .unwrap()
        .unwrap();
    assert!(
        serde_json::to_value(evidence)
            .unwrap()
            .get("offer")
            .is_none(),
        "public acceptance evidence must not retain attachment decryption keys"
    );
    fixture.restart();
    let restored = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(restored.messages.len(), 1);
    assert_eq!(
        restored.attachments[0].state,
        crate::conversation::attachments::AttachmentState::Offered
    );
}

fn attachment(
    fixture: &Fixture,
    sender: &mut MlsSessionCrypto,
    identity: &SigningKey,
) -> MossReceivedMessage {
    let session = fixture.runtime.groups.get(&fixture.id).unwrap();
    let peer = org_signing::peer_id_hex(identity);
    let mut runtime = crate::attachment_runtime::AttachmentRuntime::new();
    let mut manifest = runtime
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "recoverable-offer".into(),
            file_name: "history.txt".into(),
            mime: "text/plain".into(),
            from_fingerprint: peer.clone(),
            bytes: b"real encrypted original".to_vec(),
            thumbnail_b64: None,
            voice: None,
        })
        .unwrap();
    manifest.origin = Some(
        crate::message_deletion::MessageOrigin::sign_mls(
            &format!("group:{}", fixture.id),
            "recoverable-offer",
            &crate::message_deletion::MessageOrigin::manifest_bytes(&manifest).unwrap(),
            sender,
            None,
            Some(&peer),
        )
        .unwrap(),
    );
    let envelope = ControlEnvelope::AttachmentManifest {
        group_id: fixture.id.clone(),
        participant_id: "independent-member".into(),
        from_device: "Bob".into(),
        from_fingerprint: peer,
        sent_at_ms: Some(42),
        manifest_ciphertext_b64: sender
            .encrypt_json(&AttachmentOffer::from(manifest))
            .unwrap(),
    };
    let proof = crate::sender_auth::SenderProof::sign(
        identity,
        sender,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: serde_json::to_vec(&proof).unwrap(),
    }
}
