#[path = "support/temp_directory.rs"]
mod temp_directory;

use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::{
    PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair,
    PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey,
};
use ed25519_dalek::{Signer, SigningKey};
use mosh_core::{
    device_link::identity::DeviceIdentity, persistence::Persistence, plus::PlusRuntime,
};
use std::sync::Arc;
use temp_directory::TempDirectory;

#[test]
fn renewal_updates_peer_proof_without_replaying_over_a_newer_account_hide() {
    let directory = TempDirectory::new("mosh-mainnet-peer");
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/ietf-draft02-public-test-key.json")).unwrap();
    let sk = SecretKey::from_der(
        &STANDARD
            .decode(fixture["pkcs8_b64"].as_str().unwrap())
            .unwrap(),
    )
    .unwrap();
    let issuer = KeyPair {
        pk: sk.public_key().unwrap(),
        sk,
    };
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("sender"), [41; 32]).unwrap());
    let peer = "01".repeat(32);
    let identity = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let key = vector["public_key"].as_str().unwrap();
    let mut sender =
        PlusRuntime::open_mainnet(store, identity.roster().user_id(), key, "sender").unwrap();
    sender.save_series("series", &"a".repeat(43)).unwrap();
    let receiver_path = directory.path().join("receiver");
    let open_receiver = || {
        PlusRuntime::open_mainnet(
            Arc::new(Persistence::open_with_dek(&receiver_path, [42; 32]).unwrap()),
            "cd".repeat(32),
            key,
            "receiver",
        )
        .unwrap()
    };
    let mut receiver = open_receiver();
    let author_key = SigningKey::from_bytes(&[3; 32]);
    let author = hex::encode(author_key.verifying_key().as_bytes());
    let sign = |bytes: &[u8]| Ok(author_key.sign(bytes).to_bytes().to_vec());
    let start = 1_797_465_600_000;
    let end = 1_800_057_600_000;
    let mut last = None;
    for (id, from, until) in [("first", start, end), ("renewal", end, end + 2_592_000_000)] {
        grant(
            &mut sender,
            &issuer,
            vector["key_id"].as_str().unwrap(),
            id,
            from,
            until,
        );
        sender.set_visible(true).unwrap();
        let frame = sender
            .frame("channel:test", &peer, &author, sign, start)
            .unwrap()
            .unwrap();
        receiver
            .accept_peer(
                &frame,
                "channel:test",
                &author,
                std::slice::from_ref(&peer),
                start,
            )
            .unwrap();
        assert_eq!(receiver.snapshot(start).peer_badges.len(), 1);
        last = Some(frame);
    }
    assert_eq!(receiver.snapshot(end).peer_badges.len(), 1);
    sender.set_visible(false).unwrap();
    let hidden = sender
        .frame("channel:test", &peer, &author, sign, start)
        .unwrap()
        .unwrap();
    receiver
        .accept_peer(&hidden, "channel:test", &author, &[], start)
        .unwrap();
    receiver
        .accept_peer(&last.unwrap(), "channel:test", &author, &[], start)
        .unwrap();
    assert!(receiver.snapshot(start).peer_badges.is_empty());
    drop(receiver);
    assert!(open_receiver().snapshot(start).peer_badges.is_empty());
}

fn grant(owner: &mut PlusRuntime, issuer: &KeyPair, key_id: &str, id: &str, from: u64, until: u64) {
    owner.save_order(&serde_json::json!({ "id": id, "network": "solana-mainnet", "product": "mosh-plus-supporter-30d",
        "asset": "USDC", "token_decimals": 6, "issuer_key_id": key_id, "series_id": "series",
        "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "recipient": "11111111111111111111111111111111",
        "amount_atomic": "5000000", "reference": "So11111111111111111111111111111111111111112", "status": "paid",
        "access_token": "test-only-purchase-capability-123456789", "valid_from_ms": from, "expires_at_ms": until,
        "payment_uri": "solana:11111111111111111111111111111111?amount=5&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&reference=So11111111111111111111111111111111111111112"
    }).to_string(), from).unwrap();
    let request = owner.prepare_order_issuance(id).unwrap();
    let metadata =
        format!("mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{key_id}\0{from}\0{until}");
    let derived = issuer
        .derive_key_pair_for_metadata(metadata.as_bytes())
        .unwrap();
    let signature = derived
        .sk
        .blind_sign(STANDARD.decode(request).unwrap())
        .unwrap();
    owner
        .complete_order_issuance(id, &STANDARD.encode(signature.0), from)
        .unwrap();
}
