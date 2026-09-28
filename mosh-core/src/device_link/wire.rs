use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use ed25519_dalek::{Signature, Signer, SigningKey};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};

use super::qr::PairingQr;
use super::roster::{invalid, public_key, DeviceRoster};
use super::types::{DeviceDescriptor, Result};

pub(crate) const WIRE_PREFIX: &[u8] = b"mosh-device-link-v1\0";
pub(crate) const MAX_PACKET_BYTES: usize = 64 * 1024;
const SIGN_CONTEXT: &[u8] = b"mosh-device-packet-v1\0";
const NONCE_BYTES: usize = 12;

#[derive(Clone, Serialize, Deserialize)]
pub(crate) enum LinkMessage {
    Offer {
        roster: DeviceRoster,
        trusted: DeviceDescriptor,
    },
    Ready {
        offer_hash: String,
    },
    Approved {
        roster: DeviceRoster,
    },
    Ack {
        roster_hash: String,
    },
    Rejected,
}

#[derive(Serialize, Deserialize)]
struct SignedMessage {
    message: LinkMessage,
    signer: String,
    signature: String,
}

fn context(qr: &PairingQr, signer: &str) -> Result<Vec<u8>> {
    let mut context = SIGN_CONTEXT.to_vec();
    context.extend(qr.digest()?);
    context.extend(signer.as_bytes());
    Ok(context)
}

fn signing_bytes(qr: &PairingQr, signer: &str, message: &LinkMessage) -> Result<Vec<u8>> {
    let mut bytes = context(qr, signer)?;
    bytes.extend(serde_json::to_vec(message).map_err(|_| invalid())?);
    Ok(bytes)
}

pub(crate) fn seal(qr: &PairingQr, key: &SigningKey, message: LinkMessage) -> Result<Vec<u8>> {
    let signer = hex::encode(key.verifying_key().as_bytes());
    let signature = hex::encode(key.sign(&signing_bytes(qr, &signer, &message)?).to_bytes());
    let signed = SignedMessage {
        message,
        signer,
        signature,
    };
    let plaintext = serde_json::to_vec(&signed).map_err(|_| invalid())?;
    let mut nonce = [0; NONCE_BYTES];
    OsRng.fill_bytes(&mut nonce);
    let cipher = Aes256Gcm::new_from_slice(&qr.secret).map_err(|_| invalid())?;
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &plaintext,
                aad: &qr.digest()?,
            },
        )
        .map_err(|_| invalid())?;
    let mut packet = WIRE_PREFIX.to_vec();
    packet.extend(nonce);
    packet.extend(ciphertext);
    if packet.len() > MAX_PACKET_BYTES {
        return Err(invalid());
    }
    Ok(packet)
}

pub(crate) fn open(qr: &PairingQr, packet: &[u8]) -> Result<(String, LinkMessage)> {
    if packet.len() > MAX_PACKET_BYTES {
        return Err(invalid());
    }
    let body = packet.strip_prefix(WIRE_PREFIX).ok_or_else(invalid)?;
    if body.len() <= NONCE_BYTES {
        return Err(invalid());
    }
    let (nonce, ciphertext) = body.split_at(NONCE_BYTES);
    let cipher = Aes256Gcm::new_from_slice(&qr.secret).map_err(|_| invalid())?;
    let plaintext = cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad: &qr.digest()?,
            },
        )
        .map_err(|_| invalid())?;
    let signed: SignedMessage = serde_json::from_slice(&plaintext).map_err(|_| invalid())?;
    let key = public_key(&signed.signer)?;
    let sig = hex::decode(&signed.signature).map_err(|_| invalid())?;
    let sig = Signature::from_slice(&sig).map_err(|_| invalid())?;
    key.verify_strict(&signing_bytes(qr, &signed.signer, &signed.message)?, &sig)
        .map_err(|_| invalid())?;
    Ok((signed.signer, signed.message))
}

/// Route pairing independently of the attachment stream, which has another owner.
pub fn is_pairing_packet(bytes: &[u8]) -> bool {
    bytes.starts_with(WIRE_PREFIX)
}
