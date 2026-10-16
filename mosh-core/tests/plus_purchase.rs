#[path = "support/temp_directory.rs"]
mod temp_directory;

use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair;
use blind_rsa_signatures::pbrsa::PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey;
use ed25519_dalek::{Signer, SigningKey};
use mosh_core::device_link::identity::DeviceIdentity;
use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use std::sync::{Arc, OnceLock};
use temp_directory::TempDirectory;

fn issuer() -> &'static KeyPair {
    static ISSUER: OnceLock<KeyPair> = OnceLock::new();
    ISSUER.get_or_init(|| {
        // Public IETF vector avoids minutes of safe-prime generation in debug.
        let vector: serde_json::Value =
            serde_json::from_str(include_str!("fixtures/ietf-draft02-public-test-key.json"))
                .unwrap();
        let bytes = STANDARD
            .decode(vector["pkcs8_b64"].as_str().unwrap())
            .unwrap();
        let sk = SecretKey::from_der(&bytes).unwrap();
        KeyPair {
            pk: sk.public_key().unwrap(),
            sk,
        }
    })
}

#[test]
fn authenticated_peer_badge_updates_without_a_chat_message_and_cannot_replay_opt_out() {
    let directory = TempDirectory::new("mosh-plus-peers");
    let sender_store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("sender"), [41; 32]).unwrap());
    let peer = "01".repeat(32);
    let identity = DeviceIdentity::open(sender_store.clone(), &peer).unwrap();
    let account = identity.roster().user_id();
    let public_key = STANDARD.encode(issuer().pk.to_der().unwrap());
    let mut sender = PlusRuntime::open(sender_store, account, &public_key).unwrap();
    sender.save_order(&order(), 1_700_000_000_000).unwrap();
    let request = sender.prepare_issuance().unwrap();
    let key = issuer()
        .derive_key_pair_for_metadata(b"mosh-plus-devnet-v1\0mosh-plus-30d\01800057600000")
        .unwrap();
    let signature = key
        .sk
        .blind_sign(STANDARD.decode(request).unwrap())
        .unwrap();
    sender
        .complete_issuance(&STANDARD.encode(signature.0), 1_700_000_000_000)
        .unwrap();
    sender.set_visible(true).unwrap();
    let author_key = SigningKey::from_bytes(&[3; 32]);
    let author = hex::encode(author_key.verifying_key().as_bytes());
    let sign = |bytes: &[u8]| Ok(author_key.sign(bytes).to_bytes().to_vec());
    let frame = sender
        .frame("channel:test", &peer, &author, sign, 1_700_000_000_000)
        .unwrap()
        .unwrap();
    let receiver_store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("receiver"), [42; 32]).unwrap());
    let mut receiver = PlusRuntime::open(receiver_store, "cd".repeat(32), &public_key).unwrap();
    receiver
        .accept_peer(
            &frame,
            "channel:test",
            &author,
            std::slice::from_ref(&peer),
            1_700_000_000_000,
        )
        .unwrap();
    assert_eq!(receiver.snapshot(1_700_000_000_000).peer_badges.len(), 1);
    drop(receiver);
    let other: serde_json::Value = serde_json::from_str(include_str!("fixtures/plus-public-vector.json")).unwrap();
    let store = Arc::new(Persistence::open_with_dek(&directory.path().join("receiver"), [42; 32]).unwrap());
    let changed_issuer = PlusRuntime::open(store, "cd".repeat(32), other["public_key"].as_str().unwrap()).unwrap();
    assert!(changed_issuer.snapshot(1_700_000_000_000).peer_badges.is_empty());
    drop(changed_issuer);
    let store = Arc::new(Persistence::open_with_dek(&directory.path().join("receiver"), [42; 32]).unwrap());
    let mut receiver = PlusRuntime::open(store, "cd".repeat(32), &public_key).unwrap();
    assert!(receiver
        .accept_peer(&frame, "channel:other", &author, &[], 1_700_000_000_000)
        .is_err());
    sender.set_visible(false).unwrap();
    let hidden = sender
        .frame("channel:test", &peer, &author, sign, 1_700_000_000_000)
        .unwrap()
        .unwrap();
    receiver
        .accept_peer(
            &hidden,
            "channel:test",
            &author,
            std::slice::from_ref(&peer),
            1_700_000_000_000,
        )
        .unwrap();
    receiver
        .accept_peer(
            &frame,
            "channel:test",
            &author,
            std::slice::from_ref(&peer),
            1_700_000_000_000,
        )
        .unwrap();
    assert!(receiver.snapshot(1_700_000_000_000).peer_badges.is_empty());
}

fn order() -> String {
    serde_json::json!({
        "id": "test-purchase", "network": "solana-devnet", "product": "mosh-plus-30d",
        "mint": "So11111111111111111111111111111111111111112",
        "recipient": "11111111111111111111111111111111", "amount_atomic": "1000000001",
        "reference": "So11111111111111111111111111111111111111112", "status": "paid",
        "access_token": "test-only-purchase-capability-123456789",
        "expires_at_ms": 1_800_057_600_000_u64,
        "payment_uri": "solana:11111111111111111111111111111111?amount=1.000000001&spl-token=So11111111111111111111111111111111111111112&reference=So11111111111111111111111111111111111111112"
    }).to_string()
}

#[test]
fn purchase_resumes_the_same_blinded_request_and_retains_the_certificate_after_restart() {
    let directory = TempDirectory::new("mosh-plus-purchase");
    let path = directory.path().join("history.redb");
    let issuer_key = STANDARD.encode(issuer().pk.to_der().unwrap());
    let store = Arc::new(Persistence::open_with_dek(&path, [42; 32]).unwrap());
    let mut owner = PlusRuntime::open(store, "ab".repeat(32), &issuer_key).unwrap();
    owner.save_order(&order(), 1_700_000_000_000).unwrap();
    let blinded = owner.prepare_issuance().unwrap();
    drop(owner);
    let store = Arc::new(Persistence::open_with_dek(&path, [42; 32]).unwrap());
    let mut owner = PlusRuntime::open(store, "ab".repeat(32), &issuer_key).unwrap();
    assert_eq!(owner.prepare_issuance().unwrap(), blinded);
    let metadata = b"mosh-plus-devnet-v1\0mosh-plus-30d\01800057600000";
    let key = issuer().derive_key_pair_for_metadata(metadata).unwrap();
    let signature = key
        .sk
        .blind_sign(STANDARD.decode(&blinded).unwrap())
        .unwrap();
    owner
        .complete_issuance(&STANDARD.encode(signature.0), 1_700_000_000_000)
        .unwrap();
    assert!(owner.snapshot(1_700_000_000_000).active);
    assert!(!owner.snapshot(1_700_000_000_000).visible);
    owner.set_visible(true).unwrap();
    drop(owner);
    let store = Arc::new(Persistence::open_with_dek(&path, [42; 32]).unwrap());
    let mut owner = PlusRuntime::open(store, "ab".repeat(32), &issuer_key).unwrap();
    assert!(owner.snapshot(1_700_000_000_000).visible);
    assert!(!owner.snapshot(1_800_057_600_000).active);
    let mut next: serde_json::Value = serde_json::from_str(&order()).unwrap();
    next["id"] = "next-purchase".into();
    next["expires_at_ms"] = 1_802_736_000_000_u64.into();
    owner
        .save_order(&next.to_string(), 1_800_057_600_001)
        .unwrap();
    assert_ne!(owner.prepare_issuance().unwrap(), blinded);
}
