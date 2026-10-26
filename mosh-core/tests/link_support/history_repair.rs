//! Reproduce the old generic tail writer against a stopped generated profile.
use super::*;
use mosh_core::conversation::{
    attachments::AttachmentDirection,
    history::{History, StoredMessage},
    message_log::MessageLog,
    transfer::Transfer,
};
use mosh_core::persistence::GROUP_HISTORY;
use mosh_core::private_group_runtime::GroupMessage;

impl Peer {
    #[allow(dead_code, reason = "Shared independent-installation repair fixture.")]
    pub fn write_legacy_group_tail(&mut self, id: &str) {
        self.stop();
        let key = std::fs::read(self.dir.join("storage-key.bin")).unwrap();
        let store = Persistence::open_with_dek(
            &self.dir.join("mosh/history.redb"),
            key.try_into().unwrap(),
        )
        .unwrap();
        let attachments = Arc::new(AttachmentStore::new(self.dir.join("mosh")).unwrap());
        let mut transfer = Transfer::new(attachments);
        let mut messages = MessageLog::default();
        for row in store.list_history_messages(GROUP_HISTORY, id).unwrap() {
            let row: StoredMessage<GroupMessage> = serde_json::from_slice(&row).unwrap();
            assert!(
                row.preview_manifest.is_some(),
                "fixture needs the full original offer"
            );
            transfer.restore_stored(
                row.message.attachment.as_ref().unwrap(),
                AttachmentDirection::Incoming,
                row.attachment_manifest,
            );
            messages.upsert(row.message);
        }
        History::new(GROUP_HISTORY)
            .write_tail(&store, id, &messages, Some(&transfer))
            .unwrap();
    }
}
