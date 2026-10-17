use super::*;
use crate::sender_auth::VerifiedSender;

impl GroupSession {
    pub(super) fn sync_plus(&mut self, now: u64) -> Result<(), PrivateGroupError> {
        if !self.joined || !self.crypto.is_ready() || !self.plus_schedule.due(now) {
            return Ok(());
        }
        let Some(peer) = self.node.public_key_hex() else {
            return Ok(());
        };
        let context = &self.deletions.context;
        let author = hex::encode(self.crypto.signer_public());
        let Some(frame) = crate::plus::global::frame(
            context,
            &peer,
            &author,
            |bytes| {
                self.crypto
                    .sign_sender_proof(bytes)
                    .map_err(|e| e.to_string())
            },
            now,
        )
        .map_err(PrivateGroupError::Codec)?
        else {
            return Ok(());
        };
        let frame = crate::plus::seal_mls(&self.crypto, context, &frame)
            .map_err(PrivateGroupError::Codec)?;
        self.publish_control(&ControlEnvelope::PlusMetadata {
            group_id: self.group_id.clone(),
            frame,
        })
    }

    pub(super) fn receive_plus(
        &mut self,
        sealed: &crate::plus::SealedPlusFrame,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        if sender.mls_signer == self.crypto.signer_public() {
            return Ok(());
        }
        let context = &self.deletions.context;
        let frame = crate::plus::open_mls(&self.crypto, context, sealed)
            .map_err(PrivateGroupError::Codec)?;
        let author = hex::encode(sender.mls_signer);
        let aliases = [format!("{context}:{}", sender.peer_id), sender.peer_id];
        crate::plus::global::accept(&frame, context, &author, &aliases, now_ms())
            .map_err(PrivateGroupError::Codec)
    }
}
