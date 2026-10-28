use super::*;
use crate::conversation::{history::History, message_log::MessageLog};
use crate::private_group_runtime::durability_tests::Fixture;
use crate::test_temp_directory::TempDirectory;

pub(super) struct Original {
    pub(super) fixture: Fixture,
    pub(super) record: GroupRecord,
    pub(super) sender: crate::sender_auth::VerifiedSender,
    pub(super) row: StoredMessage<GroupMessage>,
}

impl Original {
    pub(super) fn new() -> Self {
        let mut fixture = Fixture::new();
        fixture
            .runtime
            .send_attachment_with_preview(
                &fixture.id,
                crate::conversation::previews::AttachmentInput {
                    user_transfer_id: None,
                    file_name: "original.jpg".into(),
                    mime: "image/jpeg".into(),
                    bytes: include_bytes!("../../../tests/fixtures/preview.jpg").to_vec(),
                    thumbnail: Some(encode(include_bytes!(
                        "../../../tests/fixtures/miniature.jpg"
                    ))),
                    preview: Some(include_bytes!("../../../tests/fixtures/preview.jpg").to_vec()),
                    voice: None,
                },
            )
            .unwrap();
        Self::from_fixture(fixture)
    }

    fn from_fixture(mut fixture: Fixture) -> Self {
        let row: StoredMessage<GroupMessage> =
            serde_json::from_slice(&fixture.store.list_group_messages(&fixture.id).unwrap()[0])
                .unwrap();
        let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
        let scope = session.own_history_scope().unwrap();
        let sender = scope.membership.verify_current(session).unwrap();
        let record = session
            .retained_history_record(&row, &scope, &sender.peer_id)
            .unwrap();
        session.recovery.occurrences_ready = false;
        session
            .save_history(session.recovery.checkpoint.clone(), &[], &[], &[])
            .unwrap();
        Self {
            fixture,
            record,
            sender,
            row,
        }
    }

    pub(super) fn incoming() -> Self {
        let mut fixture = Fixture::new();
        let (mut author, identity) =
            crate::private_group_runtime::durability_tests::history::member(&mut fixture);
        let peer = org_signing::peer_id_hex(&identity);
        let mut outgoing = Transfer::new(Arc::clone(fixture.runtime.groups.attachment_store()));
        let mut offer = outgoing
            .prepare_offer(
                OutgoingAttachment {
                    attachment_id: "incoming-original".into(),
                    file_name: "incoming.jpg".into(),
                    mime: "image/jpeg".into(),
                    from_fingerprint: peer.clone(),
                    bytes: include_bytes!("../../../tests/fixtures/preview.jpg").to_vec(),
                    thumbnail_b64: Some(encode(include_bytes!(
                        "../../../tests/fixtures/miniature.jpg"
                    ))),
                    voice: None,
                },
                Some(include_bytes!("../../../tests/fixtures/preview.jpg").to_vec()),
            )
            .unwrap();
        offer
            .sign_mls(&format!("group:{}", fixture.id), &author, None, Some(&peer))
            .unwrap();
        let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
        let envelope = ControlEnvelope::AttachmentManifest {
            group_id: fixture.id.clone(),
            participant_id: "independent-author".into(),
            from_device: "Bob".into(),
            from_fingerprint: peer,
            sent_at_ms: Some(42),
            manifest_ciphertext_b64: author.encrypt_json(&offer.offer()).unwrap(),
        };
        let proof = crate::sender_auth::SenderProof::sign(
            &identity,
            &author,
            &OrgContext {
                org_pubkey: "",
                mesh_id: &session.mesh_id,
                channel_kind: &session.control_channel,
            },
            serde_json::to_vec(&envelope).unwrap(),
        )
        .unwrap();
        fixture.store.save_background_intent(false, true).unwrap();
        session.handle_authenticated_control(proof).unwrap();
        fixture.runtime.poll(&fixture.id).unwrap();
        Self::from_fixture(fixture)
    }

    pub(super) fn damage(&mut self) {
        let directory = TempDirectory::new("old-group-tail");
        let mut transfer = Transfer::new(Arc::new(AttachmentStore::new(directory.path()).unwrap()));
        transfer.restore_stored(
            self.row.message.attachment.as_ref().unwrap(),
            crate::conversation::attachments::AttachmentDirection::Incoming,
            self.row.attachment_manifest.clone(),
        );
        let mut log = MessageLog::default();
        log.push(self.row.message.clone());
        History::new(GROUP_HISTORY)
            .write_tail(&self.fixture.store, &self.fixture.id, &log, Some(&transfer))
            .unwrap();
        assert!(self.saved().preview_manifest.is_none());
    }

    pub(super) fn saved(&self) -> StoredMessage<GroupMessage> {
        serde_json::from_slice(
            &self
                .fixture
                .store
                .list_group_messages(&self.fixture.id)
                .unwrap()[0],
        )
        .unwrap()
    }

    pub(super) fn session(&mut self) -> &mut GroupSession {
        self.fixture
            .runtime
            .groups
            .get_mut(&self.fixture.id)
            .unwrap()
    }
}
