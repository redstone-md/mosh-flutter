//! Live attachment notices use the MLS author, including our linked devices.
use super::*;

pub(super) fn live_offers_use_verified_ownership(f: &mut Fixture) {
    let store = f.runtime.sessions.persistence().cloned().unwrap();
    store.save_background_intent(false, true).unwrap();
    for (device, own, id) in [
        (f.source.device().device_id.clone(), true, "own-offer"),
        (f.contact.device().device_id.clone(), false, "contact-offer"),
    ] {
        receive_offer(f, &device, id);
        let snapshot = f.snapshot();
        let row = snapshot
            .messages
            .iter()
            .find(|row| row.message_id.as_deref() == Some(id))
            .unwrap();
        assert_eq!(row.metadata.as_ref().unwrap().is_own, Some(own));
    }
    let pending = store.pending_background_notifications(16).unwrap();
    assert_eq!(pending.len(), 1, "our linked device must not alert us");
    assert!(pending[0].occurrence_id.ends_with("/contact-offer"));
}

fn receive_offer(f: &mut Fixture, device: &str, id: &str) {
    let crypto = f.peers.get_mut(device).unwrap();
    let attachments = Arc::new(AttachmentStore::new(f.dir.join(device)).unwrap());
    let mut transfer = crate::conversation::transfer::Transfer::new(attachments);
    let mut outgoing = transfer
        .prepare_offer(
            crate::attachment_runtime::OutgoingAttachment {
                attachment_id: id.into(),
                file_name: "offered.bin".into(),
                mime: "application/octet-stream".into(),
                from_fingerprint: "fixture".into(),
                bytes: vec![7; 1024],
                thumbnail_b64: None,
                voice: None,
            },
            None,
        )
        .unwrap();
    outgoing
        .sign_mls(&format!("dm:{}", f.session), crypto, None, None)
        .unwrap();
    let ciphertext = crypto.encrypt_json(&outgoing.offer()).unwrap();
    let session = f.runtime.session_mut(&f.session).unwrap();
    // Even a contact claiming our display name remains a foreign MLS author.
    let envelope = crate::private_dm_runtime::ControlEnvelope::AttachmentManifest {
        session_id: f.session.clone(),
        participant_id: format!("another:{}", session.participant_id),
        from_device: session.device_id.clone(),
        manifest_ciphertext_b64: ciphertext,
    };
    session
        .handle_control(serde_json::to_vec(&envelope).unwrap())
        .unwrap();
    f.runtime.sessions.persist_tail().unwrap();
}
