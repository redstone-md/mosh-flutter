use super::*;
use crate::moss_ffi::{drain_received_messages, MOSS_TEST_LOCK};
use std::path::PathBuf;

const ORG_KEY_HEX: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn bundle(mesh: &str) -> String {
    format!("mosh://org?mesh={mesh}&name=acme#org={ORG_KEY_HEX}")
}

fn org_key() -> SigningKey {
    SigningKey::from_bytes(&[2u8; 32])
}

fn org_key_hex() -> String {
    hex::encode(org_key().verifying_key().to_bytes())
}

fn org_bundle(mesh: &str) -> String {
    format!("mosh://org?mesh={mesh}&name=acme#org={}", org_key_hex())
}

fn signed_roster(version: u64, members: &[(&str, &str, &str)]) -> Vec<u8> {
    let mut doc = serde_json::json!({
        "org_pubkey": org_key_hex(),
        "org_name": "acme",
        "version": version,
        "members": members
            .iter()
            .map(|(id, name, role)| serde_json::json!({
                "moss_peer_id": id, "name": name, "role": role,
            }))
            .collect::<Vec<_>>(),
    });
    org_roster::sign_roster(&mut doc, &org_key()).unwrap()
}

fn roster_wire(bytes: &[u8]) -> Vec<u8> {
    serde_json::to_vec(&OrgWire::Roster {
        roster_b64: encode(bytes),
    })
    .unwrap()
}

fn signed_wire(sender: &SigningKey, mesh: &str, message: &OrgMessage) -> Vec<u8> {
    let org = org_key_hex();
    let ctx = OrgContext {
        org_pubkey: &org,
        mesh_id: mesh,
        channel_kind: ORG_CHANNEL_KIND,
    };
    let env = org_envelope::sign(sender, &ctx, &serde_json::to_vec(message).unwrap());
    serde_json::to_vec(&OrgWire::Signed {
        payload_b64: encode(&env.payload),
        peer_id: env.peer_id,
        sig_b64: encode(&env.sig),
    })
    .unwrap()
}

fn identity_blob(seed: [u8; 32]) -> Vec<u8> {
    let key = SigningKey::from_bytes(&seed);
    let mut blob = vec![1u8];
    blob.extend_from_slice(&seed);
    blob.extend_from_slice(&key.verifying_key().to_bytes());
    blob.extend_from_slice(&[0u8; 64]);
    blob
}

fn temp_persistence(tag: &str, seed: [u8; 32]) -> (Arc<Persistence>, PathBuf) {
    let mut path = std::env::temp_dir();
    path.push(format!("mosh-org-rt-{tag}-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let p = Persistence::open_with_dek(&path, [9u8; 32]).expect("store should open");
    p.put_moss_identity(&identity_blob(seed)).unwrap();
    (Arc::new(p), path)
}

#[path = "org_runtime_tests/roster.rs"]
mod roster;

#[path = "org_runtime_tests/offers.rs"]
mod offers;

#[path = "org_runtime_tests/offer_recovery.rs"]
mod offer_recovery;
