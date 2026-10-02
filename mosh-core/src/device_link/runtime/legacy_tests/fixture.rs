//! Independent v1 fixtures, produced with each worker's own stored key.
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use ed25519_dalek::{Signer, SigningKey};
use mosh_core::{
    device_link::{roster::DeviceRoster, types::DeviceDescriptor},
    persistence::Persistence,
};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
struct LegacyQr {
    version: u32,
    id: String,
    expires_at: u64,
    device: DeviceDescriptor,
    secret: [u8; 32],
}

#[derive(Serialize)]
enum LegacyMessage {
    Approved { roster: DeviceRoster },
}

#[derive(Serialize)]
struct LegacySigned {
    message: LegacyMessage,
    signer: String,
    signature: String,
}

pub fn command(store: &Persistence, action: &str, command: &Value) -> Value {
    let previous = store.get_device_link().unwrap().unwrap();
    let mut identity: Value = serde_json::from_slice(&previous).unwrap();
    let response = match action {
        "legacy_base" => return identity["roster"].clone(),
        "legacy_qr" => {
            let mut secret = [0; 32];
            let mut id = [0; 16];
            OsRng.fill_bytes(&mut secret);
            OsRng.fill_bytes(&mut id);
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            return json!(LegacyQr {
                version: 1,
                id: hex::encode(id),
                expires_at: now + 300,
                device: serde_json::from_value(identity["device"].clone()).unwrap(),
                secret,
            });
        }
        "legacy_pending" => {
            identity["pending"] = json!({
                "qr": command["qr"], "trusted": command["trusted"], "base": command["base"],
            });
            json!({})
        }
        "legacy_approved" => approve(&mut identity, command),
        _ => panic!("unknown legacy fixture command"),
    };
    assert!(store
        .replace_device_link(&previous, &serde_json::to_vec(&identity).unwrap())
        .unwrap());
    response
}

fn approve(identity: &mut Value, command: &Value) -> Value {
    let qr: LegacyQr = serde_json::from_value(command["qr"].clone()).unwrap();
    let base: DeviceRoster = serde_json::from_value(command["base"].clone()).unwrap();
    let seed: [u8; 32] = serde_json::from_value(identity["seed"].clone()).unwrap();
    let key = SigningKey::from_bytes(&seed);
    let roster = base.extend(qr.device.clone(), &key).unwrap();
    let packet = seal(
        &qr,
        &key,
        LegacyMessage::Approved {
            roster: roster.clone(),
        },
    );
    identity["roster"] = json!(roster);
    identity["delivery"] = json!({
        "qr": qr, "packet": packet, "roster_hash": roster.digest().unwrap(),
    });
    json!({"roster": roster})
}

fn seal(qr: &LegacyQr, key: &SigningKey, message: LegacyMessage) -> Vec<u8> {
    let digest = Sha256::digest(serde_json::to_vec(qr).unwrap());
    let signer = hex::encode(key.verifying_key().as_bytes());
    let mut signed_bytes = b"mosh-device-packet-v1\0".to_vec();
    signed_bytes.extend(digest);
    signed_bytes.extend(signer.as_bytes());
    signed_bytes.extend(serde_json::to_vec(&message).unwrap());
    let signed = LegacySigned {
        message,
        signer,
        signature: hex::encode(key.sign(&signed_bytes).to_bytes()),
    };
    let mut nonce = [0; 12];
    OsRng.fill_bytes(&mut nonce);
    let cipher = Aes256Gcm::new_from_slice(&qr.secret).unwrap();
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &serde_json::to_vec(&signed).unwrap(),
                aad: &digest,
            },
        )
        .unwrap();
    let mut packet = b"mosh-device-link-v1\0".to_vec();
    packet.extend(nonce);
    packet.extend(ciphertext);
    packet
}
