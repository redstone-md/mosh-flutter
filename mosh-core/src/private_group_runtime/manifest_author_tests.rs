use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: PrivateGroupRuntime,
    id: String,
    peer: MlsSessionCrypto,
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
            directory,
        }
    }

    fn deliver_manifest(&mut self, outer: &str, inner: &str) {
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
        session
            .handle_moss_message(MossReceivedMessage {
                channel: session.control_channel.clone(),
                payload: serde_json::to_vec(&envelope).unwrap(),
            })
            .unwrap();
    }
}

#[test]
fn changed_outer_manifest_author_does_not_register_a_transfer_or_message() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.deliver_manifest(&"c".repeat(64), &"b".repeat(64));
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert!(snapshot.messages.is_empty());
    assert!(snapshot.attachments.is_empty());
}

#[test]
fn matching_manifest_moss_peer_id_preserves_legitimate_attachment_author() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer_id = "b".repeat(64);
    assert_ne!(peer_id, fixture.peer.fingerprint());
    fixture.deliver_manifest(&peer_id, &peer_id);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.attachments.len(), 1);
    assert_eq!(snapshot.messages[0].from_fingerprint, peer_id);
}
