use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: PrivateGroupRuntime,
    id: String,
    peer: MlsSessionCrypto,
    peer_identity: SigningKey,
    directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        crate::moss_ffi::drain_received_messages();
        let directory = TempDirectory::new("mosh-group-manifest-author");
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        let mut runtime = PrivateGroupRuntime::from_shared(moss, attachments, None);
        let id = runtime
            .create_group(CreateGroupRequest {
                label: None,
                display_name: "Alice".into(),
                listen_port: 0,
                static_peer: None,
                org_pubkey: None,
            })
            .unwrap()
            .group_id;
        let mut peer = MlsSessionCrypto::new("Bob").unwrap();
        let kp = peer.key_package_bytes().unwrap();
        let outcome = runtime
            .groups
            .get_mut(&id)
            .unwrap()
            .crypto
            .add_members(&[&kp])
            .unwrap();
        peer.join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
            .unwrap();
        Self {
            runtime,
            id,
            peer,
            peer_identity: SigningKey::from_bytes(&[5; 32]),
            directory,
        }
    }

    fn deliver_manifest(&mut self, outer: &str, inner: &str) -> Result<(), PrivateGroupError> {
        let store = Arc::new(AttachmentStore::new(self.directory.path().join("sender")).unwrap());
        let manifest = Transfer::new(store)
            .prepare_outgoing(OutgoingAttachment {
                attachment_id: "member-file".into(),
                file_name: "report.txt".into(),
                mime: "text/plain".into(),
                from_fingerprint: inner.into(),
                bytes: b"authenticated file".to_vec(),
                thumbnail_b64: None,
                voice: None,
            })
            .unwrap()
            .manifest;
        let ciphertext = self.peer.encrypt_json(&manifest).unwrap();
        let session = self.runtime.groups.get_mut(&self.id).unwrap();
        let envelope = ControlEnvelope::AttachmentManifest {
            group_id: self.id.clone(),
            participant_id: "bob-participant".into(),
            from_device: "Bob".into(),
            from_fingerprint: outer.into(),
            manifest_ciphertext_b64: ciphertext,
        };
        let proof = crate::sender_auth::SenderProof::sign(
            &self.peer_identity,
            &self.peer,
            &OrgContext {
                org_pubkey: "",
                mesh_id: &session.mesh_id,
                channel_kind: &session.control_channel,
            },
            serde_json::to_vec(&envelope).unwrap(),
        )
        .unwrap();
        session.handle_moss_message(MossReceivedMessage {
            channel: session.control_channel.clone(),
            payload: serde_json::to_vec(&proof).unwrap(),
        })
    }
}

#[test]
fn changed_outer_manifest_author_does_not_register_a_transfer_or_message() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    assert!(fixture
        .deliver_manifest(&"c".repeat(64), &"b".repeat(64))
        .is_err());
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert!(snapshot.messages.is_empty());
    assert!(snapshot.attachments.is_empty());
}

#[test]
fn matching_manifest_moss_peer_id_preserves_legitimate_attachment_author() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer_id = hex::encode(fixture.peer_identity.verifying_key().to_bytes());
    assert_ne!(peer_id, fixture.peer.fingerprint());
    fixture.deliver_manifest(&peer_id, &peer_id).unwrap();
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.attachments.len(), 1);
    assert_eq!(snapshot.messages[0].from_fingerprint, peer_id);
}

#[test]
fn matching_attacker_claims_cannot_impersonate_an_attachment_author() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let victim = fixture
        .runtime
        .groups
        .get(&fixture.id)
        .unwrap()
        .device_fingerprint
        .clone();
    assert!(fixture.deliver_manifest(&victim, &victim).is_err());
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert!(
        snapshot.messages.is_empty(),
        "member ciphertext must not authenticate a claimed author"
    );
    assert!(snapshot.attachments.is_empty());
}

#[test]
fn member_ciphertext_cannot_impersonate_a_text_author() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let ciphertext_b64 = encode(&fixture.peer.encrypt(b"forged author").unwrap());
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let envelope = DataEnvelope {
        group_id: fixture.id.clone(),
        participant_id: "bob".into(),
        from_device: "Alice".into(),
        from_fingerprint: session.device_fingerprint.clone(),
        message_id: Some("forged-message".into()),
        sent_at_ms: Some(42),
        ciphertext_b64,
    };
    let _ = session.handle_data(serde_json::to_vec(&envelope).unwrap());
    assert!(fixture
        .runtime
        .poll(&fixture.id)
        .unwrap()
        .messages
        .is_empty());
}

#[test]
fn malformed_member_plaintext_cannot_create_a_typing_indicator() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let typing_ciphertext_b64 = encode(&fixture.peer.encrypt(b"not JSON").unwrap());
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let envelope = ControlEnvelope::TypingIndicator {
        group_id: fixture.id.clone(),
        from_device: "Alice".into(),
        from_fingerprint: session.device_fingerprint.clone(),
        typing_ciphertext_b64,
    };
    let _ = session.handle_control(serde_json::to_vec(&envelope).unwrap(), None);
    assert!(fixture
        .runtime
        .poll(&fixture.id)
        .unwrap()
        .typing_members
        .is_empty());
}

#[test]
fn unsigned_control_cannot_offer_a_dm_as_another_member() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let envelope = serde_json::json!({
        "type": "DmOffer", "group_id": fixture.id,
        "offer": DmOffers::mint("Victim".into(), "c".repeat(64), session.device_fingerprint.clone(),
            "mosh://invite?mesh=attacker&session=attacker#fp=11111111111111111111111111111111".into()),
    });
    let _ = session.handle_control(serde_json::to_vec(&envelope).unwrap(), None);
    assert!(fixture
        .runtime
        .poll(&fixture.id)
        .unwrap()
        .dm_offers
        .is_empty());
}
