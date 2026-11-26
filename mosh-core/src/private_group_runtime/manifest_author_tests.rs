use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: PrivateGroupRuntime,
    id: String,
    peer: MlsSessionCrypto,
    peer_identity: SigningKey,
    /// Bob's side of the file: it seals the manifest and serves the chunks.
    sender: Transfer,
    _directory: TempDirectory,
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
        let sender_store = Arc::new(AttachmentStore::new(directory.path().join("sender")).unwrap());
        Self {
            runtime,
            id,
            peer,
            peer_identity: SigningKey::from_bytes(&[5; 32]),
            sender: Transfer::new(sender_store),
            _directory: directory,
        }
    }

    fn deliver_manifest(&mut self, outer: &str, inner: &str) -> Result<(), PrivateGroupError> {
        let manifest = self
            .sender
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
            sent_at_ms: None,
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

    /// Bob's answer to a request for the whole file, as the blob frames he
    /// publishes. Serving the same chunk again yields the same bytes.
    fn served_chunks(&mut self) -> Vec<MossReceivedMessage> {
        let blob_channel = self.runtime.groups[&self.id].blob_channel.clone();
        let request = crate::attachment_runtime::ChunkRequest {
            attachment_id: "member-file".into(),
            chunk_indices: vec![0],
            execution: None,
        };
        let frames = self.sender.serve(&request);
        assert!(!frames.is_empty(), "Bob holds the file");
        frames
            .into_iter()
            .map(|frame| MossReceivedMessage {
                channel: blob_channel.clone(),
                payload: serde_json::to_vec(&BlobEnvelope::Chunk {
                    participant_id: "bob-participant".into(),
                    frame,
                })
                .unwrap(),
            })
            .collect()
    }
}

// A member who saw Bob's chunks go by before asking for the file (another
// member was downloading it) must still take them when Bob serves them again
// for its own download. Chunk frames are deterministic, so the re-served ones
// are byte-identical to what passed earlier.
#[test]
fn a_chunk_seen_before_the_download_is_taken_when_served_again() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer_id = hex::encode(fixture.peer_identity.verifying_key().to_bytes());
    fixture.deliver_manifest(&peer_id, &peer_id).unwrap();
    let chunks = fixture.served_chunks();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    for chunk in chunks.clone() {
        session.handle_moss_message(chunk).unwrap();
    }

    fixture
        .runtime
        .download_attachment(&fixture.id, "member-file")
        .unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    for chunk in chunks {
        session.handle_moss_message(chunk).unwrap();
    }

    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(
        snapshot.attachments[0].state,
        crate::conversation::attachments::AttachmentState::Available
    );
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
        origin: None,
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
