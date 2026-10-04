use super::*;

impl MlsSessionCrypto {
    /// Serialize one control payload into base64 MLS ciphertext.
    pub(crate) fn encrypt_json<T: serde::Serialize>(
        &mut self,
        value: &T,
    ) -> Result<String, MlsCryptoError> {
        let bytes = serde_json::to_vec(value).map_err(MlsCryptoError::codec)?;
        self.encrypt(&bytes)
            .map(|encrypted| crate::conversation::encode(&encrypted))
    }

    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        group
            .create_message(&self.provider, &self.signer, plaintext)
            .map_err(MlsCryptoError::openmls)?
            .to_bytes()
            .map_err(MlsCryptoError::codec)
    }

    pub fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, MlsCryptoError> {
        self.decrypt_with_signer(ciphertext).map(|(body, _)| body)
    }

    /// A member can wrap another member's ciphertext in their own valid
    /// outer proof. Reject that mismatch without consuming the receive ratchet.
    pub(crate) fn decrypt_from_signer(
        &mut self,
        ciphertext: &[u8],
        expected: &[u8],
    ) -> Result<Vec<u8>, MlsCryptoError> {
        let identity = Self::credential_identity(&self.credential.credential)
            .ok_or(MlsCryptoError::NotReady)?;
        let group_id = self.group_id_bytes().ok_or(MlsCryptoError::NotReady)?;
        let mut candidate = Self::restore(
            &identity,
            &self.signer_public(),
            &self.snapshot(),
            &group_id,
        )?;
        let (body, signer) = candidate.decrypt_with_signer(ciphertext)?;
        if signer != expected {
            return Err(MlsCryptoError::OpenMls(
                "ciphertext signer differs from sender proof".into(),
            ));
        }
        *self = candidate;
        Ok(body)
    }

    /// Return the verified leaf signer with its application plaintext.
    pub(crate) fn decrypt_with_signer(
        &mut self,
        ciphertext: &[u8],
    ) -> Result<(Vec<u8>, Vec<u8>), MlsCryptoError> {
        let group = self.group.as_mut().ok_or(MlsCryptoError::NotReady)?;
        let message =
            MlsMessageIn::tls_deserialize(&mut &ciphertext[..]).map_err(MlsCryptoError::codec)?;
        let protocol_message = message
            .try_into_protocol_message()
            .map_err(MlsCryptoError::codec)?;
        let processed = group
            .process_message(&self.provider, protocol_message)
            .map_err(MlsCryptoError::openmls)?;
        let signer = match processed.sender() {
            Sender::Member(index) => group
                .members()
                .find(|member| member.index == *index)
                .map(|member| member.signature_key)
                .ok_or(MlsCryptoError::NotReady)?,
            _ => return Err(MlsCryptoError::NotReady),
        };
        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(message) => {
                Ok((message.into_bytes(), signer))
            }
            _ => Err(MlsCryptoError::OpenMls(
                "expected application message".to_string(),
            )),
        }
    }

    pub fn fingerprint(&self) -> String {
        fingerprint_from_signature_key(&self.signer.to_public_vec())
    }

    pub fn random_token(&self, prefix: &str) -> Result<String, MlsCryptoError> {
        let bytes = self
            .provider
            .rand()
            .random_array::<8>()
            .map_err(MlsCryptoError::openmls)?;
        let suffix = hex::encode(bytes);
        Ok(format!("{prefix}-{suffix}"))
    }

    pub fn is_ready(&self) -> bool {
        self.group.is_some()
    }

    /// Current group epoch; `None` before the group exists.
    pub fn epoch(&self) -> Option<u64> {
        self.group.as_ref().map(|g| g.epoch().as_u64())
    }

    /// Wire-header epoch of a serialized commit — readable without processing
    /// (the epoch sits in the header for public and private messages alike).
    pub fn commit_epoch(commit_bytes: &[u8]) -> Result<u64, MlsCryptoError> {
        let message =
            MlsMessageIn::tls_deserialize(&mut &commit_bytes[..]).map_err(MlsCryptoError::codec)?;
        let protocol_message = message
            .try_into_protocol_message()
            .map_err(MlsCryptoError::codec)?;
        Ok(protocol_message.epoch().as_u64())
    }
}
