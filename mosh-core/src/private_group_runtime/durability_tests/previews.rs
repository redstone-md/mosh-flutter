use super::*;
use crate::conversation::previews::AttachmentInput;

const PREVIEW: &[u8] = include_bytes!("../../../tests/fixtures/preview.jpg");
const MINIATURE: &[u8] = include_bytes!("../../../tests/fixtures/miniature.jpg");

fn input() -> AttachmentInput {
    let mut miniature = MINIATURE.to_vec();
    miniature.resize(1536, 0);
    AttachmentInput {
        file_name: "Bildschirmfoto 2026-10-05 um 21.31.39.png".into(),
        mime: "image/png".into(),
        bytes: PREVIEW.to_vec(),
        thumbnail: Some(encode(&miniature)),
        preview: Some(PREVIEW.to_vec()),
        voice: None,
    }
}

#[test]
fn a_large_legacy_thumbnail_reports_size_and_does_not_pin_a_transfer() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let mut image = input();
    let mut legacy_preview = PREVIEW.to_vec();
    legacy_preview.resize(22_710, 0);
    image.thumbnail = Some(encode(&legacy_preview));
    image.preview = None;
    let error = fixture
        .runtime
        .send_attachment_with_preview(&fixture.id, image)
        .unwrap_err();
    let bridge: crate::api::conversation_bridge::ConversationBridgeError = error.into();
    assert_eq!(
        bridge.kind,
        crate::api::conversation_bridge::ConversationBridgeErrorKind::PayloadTooLarge
    );
    let session = fixture.runtime.groups.get(&fixture.id).unwrap();
    assert!(session.transfer.views().is_empty());
    let descriptor = AttachmentDescriptor {
        attachment_id: "unpublished".into(),
        file_name: input().file_name,
        mime: "image/png".into(),
        content_hash: crate::attachment_crypto::sha256_hex(PREVIEW),
        total_size: PREVIEW.len() as u64,
        thumbnail_b64: None,
        voice: None,
    };
    assert!(session.transfer.clean_erased(&descriptor, None).unwrap());
}

#[test]
fn the_signed_offer_fits_org_wrapping_and_sender_restarts_serve_the_preview() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let sent = fixture
        .runtime
        .send_attachment_with_preview(&fixture.id, input())
        .unwrap();
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.messages.len(), 1);
    assert!(snapshot.attachments[0].preview_path.is_some());
    fixture.restart();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let manifest = session.transfer.manifest_for(&sent.attachment_id).unwrap();
    let preview_manifest = session
        .transfer
        .preview_manifest_for(&sent.attachment_id)
        .unwrap();
    let offer = AttachmentOffer {
        manifest,
        preview_manifest: Some(preview_manifest),
    };
    offer
        .verify(
            &format!("group:{}", fixture.id),
            Some(&session.crypto.signer_public()),
        )
        .unwrap();
    let ciphertext = session.crypto.encrypt_json(&offer).unwrap();
    let proof = session
        .sign_application(
            &ControlEnvelope::AttachmentManifest {
                group_id: fixture.id.clone(),
                participant_id: session.participant_id.clone(),
                from_device: session.display_name.clone(),
                from_fingerprint: session.device_fingerprint.clone(),
                manifest_ciphertext_b64: ciphertext,
            },
            &session.control_channel,
        )
        .unwrap();
    let wrapped = org_envelope::sign(
        session.node.identity_signer().unwrap(),
        &OrgContext {
            org_pubkey: &"a".repeat(64),
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        &serde_json::to_vec(&proof).unwrap(),
    );
    let payload = serde_json::to_vec(&wrapped).unwrap();
    assert!(payload.len() <= 65_536, "{} exceeds Moss", payload.len());
    session
        .node
        .publish_room_best_effort(&session.mesh_id, &session.control_channel, &payload)
        .unwrap();
    let receiver_dir = TempDirectory::new("mosh-preview-restored-receiver");
    let mut receiver = Transfer::new(Arc::new(AttachmentStore::new(receiver_dir.path()).unwrap()));
    receiver.accept_offer(offer).unwrap();
    for request in receiver.next_requests() {
        for chunk in session.transfer.serve(&request) {
            receiver.ingest(&chunk).unwrap();
        }
    }
    assert!(receiver.preview_path(&sent.attachment_id).is_some());
}
