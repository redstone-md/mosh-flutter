use super::*;
use crate::conversation::previews::{AttachmentOffer, MAX_PREVIEW_BYTES};
use ed25519_dalek::SigningKey;

fn signed_offer(transfer: &mut Transfer, id: &str) -> AttachmentOffer {
    let mut outgoing = transfer
        .prepare_offer(
            super::previews::image(id),
            Some(super::previews::PREVIEW.to_vec()),
        )
        .unwrap();
    outgoing
        .sign("channel:photos", &SigningKey::from_bytes(&[3; 32]), None)
        .unwrap();
    outgoing.offer()
}

#[test]
fn a_legacy_reader_verifies_the_original_manifest_without_the_preview_field() {
    let scratch = Scratch::open("preview-legacy-proof");
    let offer = signed_offer(&mut scratch.transfer(), "photo");
    let wire = serde_json::to_vec(&offer).unwrap();
    let legacy: AttachmentManifest = serde_json::from_slice(&wire).unwrap();
    legacy
        .origin
        .as_ref()
        .unwrap()
        .verify_manifest("channel:photos", &legacy)
        .unwrap();
    assert_eq!(legacy.thumbnail_b64, offer.manifest.thumbnail_b64);
    offer.verify("channel:photos", None).unwrap();
    let decoded: AttachmentOffer =
        serde_json::from_slice(&serde_json::to_vec(&legacy).unwrap()).unwrap();
    assert!(decoded.preview_manifest.is_none());
    decoded.verify("channel:photos", None).unwrap();
}

#[test]
fn swapped_unsigned_or_modified_previews_are_rejected() {
    let scratch = Scratch::open("preview-proof-binding");
    let mut transfer = scratch.transfer();
    let offer = signed_offer(&mut transfer, "photo");
    let other = signed_offer(&mut transfer, "other");
    let mut variants = Vec::new();
    let mut swapped = offer.clone();
    swapped.preview_manifest = other.preview_manifest;
    variants.push(swapped);
    let mut unsigned = offer.clone();
    unsigned.manifest.origin = None;
    variants.push(unsigned);
    let mut tampered = offer.clone();
    tampered.preview_manifest.as_mut().unwrap().content_hash = "0".repeat(64);
    variants.push(tampered);
    let mut wrong_signer = offer.clone();
    let child = wrong_signer.preview_manifest.as_mut().unwrap();
    child.origin = Some(
        crate::message_deletion::MessageOrigin::sign(
            "channel:photos/preview/photo",
            &child.attachment_id,
            &crate::message_deletion::MessageOrigin::manifest_bytes(child).unwrap(),
            &SigningKey::from_bytes(&[4; 32]),
            None,
        )
        .unwrap(),
    );
    variants.push(wrong_signer);
    for variant in variants {
        assert!(variant.verify("channel:photos", None).is_err());
    }
    assert!(offer.verify("channel:elsewhere", None).is_err());
}

#[test]
fn unbounded_or_non_image_preview_descriptors_open_no_downloads() {
    let sent = Scratch::open("preview-invalid-sender");
    let received = Scratch::open("preview-invalid-receiver");
    let offer = signed_offer(&mut sent.transfer(), "photo");
    let mut variants = Vec::new();
    let mut huge = offer.clone();
    huge.preview_manifest.as_mut().unwrap().total_size = MAX_PREVIEW_BYTES + 1;
    variants.push(huge);
    let mut oversized_miniature = offer.clone();
    oversized_miniature.manifest.thumbnail_b64 = Some("A".repeat(3000));
    variants.push(oversized_miniature);
    let mut file = offer.clone();
    file.manifest.mime = "application/pdf".into();
    variants.push(file);
    let mut key = offer.clone();
    key.preview_manifest.as_mut().unwrap().key_b64 = "bad key".into();
    variants.push(key);
    for variant in variants {
        let mut receiver = received.transfer();
        assert!(receiver.accept_offer(variant).is_err());
        assert!(receiver.views().is_empty());
        assert!(receiver.next_requests().is_empty());
    }
}

#[test]
fn restarting_revalidates_cached_previews_and_resumes_missing_ones() {
    let sent = Scratch::open("preview-restart-sender");
    let received = Scratch::open("preview-restart-receiver");
    let mut sender = sent.transfer();
    let offer = signed_offer(&mut sender, "photo");
    let descriptor = descriptor_of(&offer.manifest);
    let child = offer.preview_manifest.as_ref().unwrap();
    let cached = received
        .store
        .write_blob(
            &child.content_hash,
            &child.file_name,
            super::previews::PREVIEW,
        )
        .unwrap();
    let mut restored = received.transfer();
    restored.restore_stored(
        &descriptor,
        AttachmentDirection::Incoming,
        Some(offer.manifest.clone()),
    );
    restored.restore_preview(offer.clone(), AttachmentDirection::Incoming);
    assert!(restored.preview_path("photo").is_some());
    assert!(restored.next_requests().is_empty());
    drop(restored);
    std::fs::write(cached, vec![0; child.total_size as usize]).unwrap();
    let mut restarted = received.transfer();
    restarted.restore_stored(
        &descriptor,
        AttachmentDirection::Incoming,
        Some(offer.manifest.clone()),
    );
    restarted.restore_preview(offer, AttachmentDirection::Incoming);
    assert!(restarted.preview_path("photo").is_none());
    assert_eq!(restarted.next_requests()[0].attachment_id, "photo/preview");
}

#[test]
fn repeated_history_rows_do_not_consume_distinct_preview_download_slots() {
    let sent = Scratch::open("preview-duplicate-sender");
    let received = Scratch::open("preview-duplicate-receiver");
    let mut sender = sent.transfer();
    let mut receiver = received.transfer();
    for index in 0..4 {
        let offer = signed_offer(&mut sender, &format!("photo-{index}"));
        for _ in 0..4 {
            receiver.restore_preview(offer.clone(), AttachmentDirection::Incoming);
        }
    }
    let requests = receiver.next_requests();
    assert_eq!(requests.len(), 4, "four distinct previews must start");
    let active = requests[0].attachment_id.trim_end_matches("/preview");
    let offer = signed_offer(&mut sender, "later");
    receiver.restore_preview(offer, AttachmentDirection::Incoming);
    // Replaying an already active preview must not restart its download.
    receiver.restore_preview(
        signed_offer(&mut sent.transfer(), active),
        AttachmentDirection::Incoming,
    );
    assert!(receiver.next_requests().is_empty());
}
