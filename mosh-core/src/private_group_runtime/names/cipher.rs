//! Metadata uses an MLS exporter key, leaving legacy message ratchets untouched.
use super::*;
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use rand::{rngs::OsRng, RngCore};

const LABEL: &str = "mosh-group-chat-names-v1";

impl GroupSession {
    fn names_cipher(&self) -> Result<Aes256Gcm, PrivateGroupError> {
        let key = self.crypto.metadata_key(LABEL, self.group_id.as_bytes())?;
        Aes256Gcm::new_from_slice(&key).map_err(|e| PrivateGroupError::Codec(e.to_string()))
    }

    pub(in crate::private_group_runtime) fn seal_name<T: Serialize>(
        &self,
        value: &T,
    ) -> Result<String, PrivateGroupError> {
        let bytes =
            serde_json::to_vec(value).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let mut nonce = [0; 12];
        OsRng.fill_bytes(&mut nonce);
        let ciphertext = self
            .names_cipher()?
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: &bytes,
                    aad: self.group_id.as_bytes(),
                },
            )
            .map_err(|_| PrivateGroupError::Codec("name encryption failed".into()))?;
        let mut frame = nonce.to_vec();
        frame.extend(ciphertext);
        Ok(encode(&frame))
    }

    pub(super) fn open_name(&self, epoch: u64, frame: &str) -> Result<Vec<u8>, PrivateGroupError> {
        if self.crypto.epoch() != Some(epoch) {
            return Err(PrivateGroupError::NotReady);
        }
        if frame.len() > 65536 {
            return Err(PrivateGroupError::Codec("name frame too large".into()));
        }
        let bytes = decode(frame)?;
        if bytes.len() < 28 {
            return Err(PrivateGroupError::Codec("truncated name frame".into()));
        }
        self.names_cipher()?
            .decrypt(
                Nonce::from_slice(&bytes[..12]),
                Payload {
                    msg: &bytes[12..],
                    aad: self.group_id.as_bytes(),
                },
            )
            .map_err(|_| PrivateGroupError::Codec("invalid name ciphertext".into()))
    }
}
