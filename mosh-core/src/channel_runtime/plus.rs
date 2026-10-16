use super::*;
use ed25519_dalek::Signer;

impl ChannelSession {
    pub(super) fn sync_plus(&mut self, now: u64) -> Result<(), ChannelRuntimeError> {
        if !self.plus_schedule.due(now) {
            return Ok(());
        }
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        let Some(frame) = crate::plus::global::frame(
            &self.deletions.context,
            &self.device_fingerprint,
            &self.device_fingerprint,
            |bytes| Ok(key.sign(bytes).to_bytes().to_vec()),
            now,
        )
        .map_err(ChannelRuntimeError::Codec)?
        else {
            return Ok(());
        };
        publish_json(
            &self.node,
            &self.mesh_id,
            &self.blob_topic,
            &ChannelBlobEnvelope::PlusMetadata { frame },
        )
    }

    pub(super) fn receive_plus(
        &mut self,
        frame: &crate::plus::PlusFrame,
    ) -> Result<(), ChannelRuntimeError> {
        if frame.author == self.device_fingerprint {
            return Ok(());
        }
        let context = &self.deletions.context;
        let aliases = [format!("{context}:{}", frame.author), frame.author.clone()];
        crate::plus::global::accept(
            frame,
            context,
            &frame.author,
            &aliases,
            crate::conversation::now_ms(),
        )
        .map_err(ChannelRuntimeError::Codec)
    }
}
