use super::protocol::{DeletionFrame, DeletionMessage};
use crate::{
    conversation::{decode, encode},
    mls_crypto::MlsSessionCrypto,
};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use ed25519_dalek::{Signer, SigningKey};
use rand::RngCore;

fn cipher(crypto: &MlsSessionCrypto, context: &str) -> Result<Aes256Gcm, String> {
    let key = crypto
        .metadata_key("mosh-message-deletions-v1", context.as_bytes())
        .map_err(|e| e.to_string())?;
    Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())
}

pub(crate) fn seal_mls(
    context: &str,
    crypto: &MlsSessionCrypto,
    message: &DeletionMessage,
) -> Result<DeletionFrame, String> {
    let bytes = serde_json::to_vec(message).map_err(|e| e.to_string())?;
    let mut nonce = [0; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let encrypted = cipher(crypto, context)?
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &bytes,
                aad: context.as_bytes(),
            },
        )
        .map_err(|_| "deletion encryption failed")?;
    let mut payload = nonce.to_vec();
    payload.extend(encrypted);
    let mut frame = DeletionFrame {
        context: context.into(),
        epoch: crypto.epoch().ok_or("MLS not ready")?,
        author: hex::encode(crypto.signer_public()),
        payload_b64: encode(&payload),
        signature: String::new(),
    };
    frame.signature = hex::encode(
        crypto
            .sign_sender_proof(&frame.input()?)
            .map_err(|e| e.to_string())?,
    );
    Ok(frame)
}

pub(crate) fn open_mls(
    context: &str,
    crypto: &MlsSessionCrypto,
    frame: &DeletionFrame,
) -> Result<DeletionMessage, String> {
    frame.verify(context)?;
    if crypto.epoch() != Some(frame.epoch) {
        return Err("deletion epoch differs".into());
    }
    let bytes = decode(&frame.payload_b64).map_err(|e| e.to_string())?;
    if bytes.len() < 28 {
        return Err("truncated deletion frame".into());
    }
    let decrypted = cipher(crypto, context)?
        .decrypt(
            Nonce::from_slice(&bytes[..12]),
            Payload {
                msg: &bytes[12..],
                aad: context.as_bytes(),
            },
        )
        .map_err(|_| "invalid deletion ciphertext")?;
    serde_json::from_slice(&decrypted).map_err(|e| e.to_string())
}

pub(crate) fn seal_channel(
    context: &str,
    key: &SigningKey,
    message: &DeletionMessage,
) -> Result<DeletionFrame, String> {
    let bytes = serde_json::to_vec(&(crate::message_id::occurrence_id("frame"), message))
        .map_err(|e| e.to_string())?;
    let mut frame = DeletionFrame {
        context: context.into(),
        epoch: 0,
        author: hex::encode(key.verifying_key().as_bytes()),
        payload_b64: encode(&bytes),
        signature: String::new(),
    };
    frame.signature = hex::encode(key.sign(&frame.input()?).to_bytes());
    Ok(frame)
}

pub(crate) fn open_channel(
    context: &str,
    frame: &DeletionFrame,
) -> Result<DeletionMessage, String> {
    frame.verify(context)?;
    let (_, message): (String, DeletionMessage) =
        serde_json::from_slice(&decode(&frame.payload_b64).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    Ok(message)
}
