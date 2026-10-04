//! Text encoding is shared by first sends and migration of saved retries.
use super::*;

impl GroupSession {
    pub(super) fn encode_text(
        &mut self,
        message: &GroupMessage,
    ) -> Result<(Vec<u8>, usize), PrivateGroupError> {
        let ciphertext = self.crypto.encrypt(message.body.as_bytes())?;
        let envelope = DataEnvelope {
            group_id: self.group_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: message.from_device.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            message_id: message.message_id.clone(),
            sent_at_ms: message.sent_at_ms,
            ciphertext_b64: encode(&ciphertext),
        };
        let proof = self.sign_application(&envelope, &self.data_channel)?;
        let payload = serde_json::to_vec(&proof)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        Ok((payload, ciphertext.len()))
    }

    /// Re-encrypt deliberate retries from the encrypted local message record.
    /// This upgrades legacy frames and uses the current epoch after restoration,
    /// including a previous snapshot refusal. Network frames cannot enter here.
    pub(super) fn prepare_retry(&mut self, id: &str) -> Result<(), PrivateGroupError> {
        let Some(attempt) = self.outbound_attempts.get(id) else {
            return Ok(());
        };
        let message: GroupMessage = serde_json::from_str(&attempt.message_json)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        let (payload, ciphertext_bytes) = self.encode_text(&message)?;
        if let Some(attempt) = self.outbound_attempts.get_mut(id) {
            attempt.publish_payload_b64 = encode(&payload);
            attempt.ciphertext_bytes = ciphertext_bytes;
        }
        Ok(())
    }
}
