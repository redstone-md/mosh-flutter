#[path = "support/temp_directory.rs"]
mod temp_directory;

use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::{
    PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair,
    PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey,
};
use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use std::sync::Arc;
use temp_directory::TempDirectory;

#[test]
fn renewal_keeps_current_access_and_future_certificate_across_restart() {
    let directory = TempDirectory::new("mosh-mainnet-periods");
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
    let path = directory.path().join("history");
    let open = || {
        PlusRuntime::open_mainnet(
            Arc::new(Persistence::open_with_dek(&path, [42; 32]).unwrap()),
            "ab".repeat(32),
            vector["public_key"].as_str().unwrap(),
            "device-one",
        )
        .unwrap()
    };
    let mut owner = open();
    owner.save_series("series-one", &"a".repeat(43)).unwrap();
    let start = 1_797_465_600_000_u64;
    let end = 1_800_057_600_000_u64;
    for (id, from, until) in [("first", start, end), ("second", end, end + 2_592_000_000)] {
        let order = serde_json::json!({ "id": id, "network": "solana-mainnet",
            "product": "mosh-plus-supporter-30d", "asset": "USDC", "token_decimals": 6,
            "issuer_key_id": vector["key_id"], "series_id": "series-one",
            "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "recipient": "11111111111111111111111111111111", "amount_atomic": "5000000",
            "reference": "So11111111111111111111111111111111111111112", "status": "paid",
            "access_token": "test-only-purchase-capability-123456789",
            "valid_from_ms": from, "expires_at_ms": until,
            "payment_uri": "solana:11111111111111111111111111111111?amount=5&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&reference=So11111111111111111111111111111111111111112"
        });
        owner.save_order(&order.to_string(), start).unwrap();
        let blind = owner.prepare_order_issuance(id).unwrap();
        let metadata = format!(
            "mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{}\0{from}\0{until}",
            vector["key_id"].as_str().unwrap()
        );
        let key = issuer
            .derive_key_pair_for_metadata(metadata.as_bytes())
            .unwrap();
        let reply = key.sk.blind_sign(STANDARD.decode(blind).unwrap()).unwrap();
        owner
            .complete_order_issuance(id, &STANDARD.encode(reply.0), start)
            .unwrap();
    }
    assert!(owner.snapshot(start).active);
    assert!(!owner.snapshot(start).visible);
    assert_eq!(
        owner.snapshot(start).expires_at_ms,
        Some(end + 2_592_000_000)
    );
    owner.set_visible(true).unwrap();
    drop(owner);
    let owner = open();
    assert!(owner.snapshot(end).active);
    assert!(owner.snapshot(end).visible);
    assert!(!owner.snapshot(start - 1).active);
    assert!(!owner.snapshot(end + 2_592_000_000).active);
    assert_eq!(owner.snapshot(start).orders.len(), 2);
}
