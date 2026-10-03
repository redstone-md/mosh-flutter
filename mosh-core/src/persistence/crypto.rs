use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::RngCore;

use super::PersistenceError;

const NONCE_LEN: usize = 12;

/// AES-256-GCM. Output layout: [12-byte nonce][ciphertext+tag].
pub fn encrypt_blob(dek: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, PersistenceError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(dek));
    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| PersistenceError::Crypto(e.to_string()))?;
    let mut out = Vec::with_capacity(NONCE_LEN + ct.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn decrypt_blob(dek: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, PersistenceError> {
    if blob.len() < NONCE_LEN {
        return Err(PersistenceError::Crypto("blob shorter than nonce".into()));
    }
    let (nonce_bytes, ct) = blob.split_at(NONCE_LEN);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(dek));
    cipher
        .decrypt(Nonce::from_slice(nonce_bytes), ct)
        .map_err(|e| PersistenceError::Crypto(e.to_string()))
}
