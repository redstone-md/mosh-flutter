//! Authenticated read receipts and peer address hints.

use super::*;

impl PrivateDmSession {
    pub(super) fn accept_read_receipt(
        &mut self,
        receipt_ciphertext_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        // Decrypting authenticates: only the MLS peer can produce a
        // ciphertext this group accepts, so a forged receipt stops
        // here and the ticks keep their color. The symmetry rule
        // lives in the runtime: when this user does not send
        // receipts, the inbound ones are dropped unread.
        let Some(true) =
            crate::read_receipts::load(&crate::api::shared_runtime::resolved_data_dir())
                .map(|setting| setting.enabled)
        else {
            return Ok(());
        };
        let Ok(ciphertext) = decode(receipt_ciphertext_b64) else {
            return Ok(());
        };
        let legacy_author = self.peer_display_name.clone().unwrap_or_default();
        let Ok(frame) = self.decrypt_contact_control(&ciphertext, &legacy_author) else {
            dlog::write(
                LogLevel::Warn,
                kinds::VERIFY,
                &self.session_id,
                "dropping unverifiable read receipt",
            );
            return Ok(());
        };
        let Some((plaintext, author)) = frame else {
            return Ok(());
        };
        let Ok(body) = decode_json::<ReadReceiptBody>(&plaintext) else {
            return Ok(());
        };
        self.note_authenticated_frame(&author);
        self.note_peer_read(&body.message_id);
        Ok(())
    }
    pub(super) fn accept_peer_announce(
        &mut self,
        from_device: &str,
        moss_peer_id: String,
    ) -> Result<(), PrivateDmRuntimeError> {
        // Verified rosters own linked-client addresses; plaintext hints do not.
        if self.devices_live() {
            return Ok(());
        }
        let was_unknown = self.peer_moss_id.is_none();
        self.note_peer_name(from_device);
        self.note_peer_moss_id(Some(moss_peer_id));
        // Answer once, and only to an announce that told us something
        // new: the peer announces because IT is missing our id, and
        // without this reply a pair that both restarted would each wait
        // for the other. Answering unconditionally would instead ping-
        // pong forever between two sides that already know each other.
        if was_unknown {
            let _ = self.publish_peer_announce();
        }
        Ok(())
    }
}
