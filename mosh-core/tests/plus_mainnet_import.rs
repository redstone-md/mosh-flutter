#[path = "support/temp_directory.rs"]
mod temp_directory;

use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use serde_json::{json, Value};
use std::sync::Arc;
use temp_directory::TempDirectory;

fn open(directory: &TempDirectory) -> PlusRuntime {
    let vector: Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    PlusRuntime::open_mainnet(
        Arc::new(Persistence::open_with_dek(&directory.path().join("history"), [42; 32]).unwrap()),
        "ab".repeat(32),
        vector["public_key"].as_str().unwrap(),
        "founder",
    )
    .unwrap()
}

fn paid_order() -> Value {
    let vector: Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    json!({ "id":"order", "network":"solana-mainnet", "product":"mosh-plus-supporter-30d",
        "asset":"USDC", "mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "token_decimals":6,
        "recipient":"11111111111111111111111111111111", "amount_atomic":"5000000",
        "reference":"So11111111111111111111111111111111111111112", "status":"paid",
        "access_token":"test-only-capability-12345678901234567890", "series_id":"series", "request_id":"request",
        "issuer_key_id":vector["key_id"], "valid_from_ms":vector["valid_from_ms"], "expires_at_ms":vector["expires_at_ms"],
        "payment_uri":"solana:11111111111111111111111111111111?amount=5&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&reference=So11111111111111111111111111111111111111112" })
}

#[test]
fn an_accepted_offer_rejects_repricing_and_keeps_the_checkout_retryable() {
    let directory = TempDirectory::new("mosh-checkout-terms");
    let mut owner = open(&directory);
    owner
        .reconcile_plus_roster("roster", "founder", &["founder".into()])
        .unwrap();
    let series = owner.prepare_series().unwrap();
    owner.confirm_series_registered(&series.id).unwrap();
    owner.prepare_checkout("USDC").unwrap();
    let mut order = paid_order();
    order["series_id"] = json!(series.id);
    order["request_id"] = json!(owner.snapshot(0).checkout_intent.unwrap().request_id);
    let terms = json!({ "asset":"USDC", "network":order["network"], "product":order["product"],
        "issuer_key_id":order["issuer_key_id"], "amount_atomic":"6000000" });
    owner.bind_checkout_offer(&terms.to_string()).unwrap();
    assert!(owner.save_order(&order.to_string(), 0).is_err());
    assert!(owner.snapshot(0).checkout_intent.is_some());
    assert!(owner.save_schedule("other-series", 0).is_err());
    assert!(owner.save_schedule(&series.id, 1).is_err());
    owner.save_schedule(&series.id, 1_800_057_600_000).unwrap();
    owner.save_schedule(&series.id, 0).unwrap();
    assert_eq!(owner.snapshot(0).reserved_until_ms, Some(1_800_057_600_000));
}

#[test]
fn synchronized_certificates_match_immutable_paid_intervals_and_reject_foreign_writers() {
    let directory = TempDirectory::new("mosh-sync-interval");
    let mut owner = open(&directory);
    let vector: Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let certificate = json!({ "account_id":"ab".repeat(32), "expires_at_ms":vector["expires_at_ms"],
        "signature_b64":vector["signature"], "mainnet":{
            "issuer_key_id":vector["key_id"], "valid_from_ms":vector["valid_from_ms"] } });
    let page = json!({ "account":"ab".repeat(32), "issuer":vector["key_id"],
        "series":null, "committed":false, "counter":0, "writer":"", "visible":false,
        "items":[{ "order":paid_order(), "writer":"founder", "prepared":null, "certificate":certificate }], "next":null });
    let mut mismatched = page.clone();
    mismatched["items"][0]["order"]["expires_at_ms"] = json!(1_800_144_000_000_u64);
    assert!(owner.merge_sync(&mismatched.to_string()).is_err());
    assert!(owner.snapshot(1_797_465_600_000).orders.is_empty());
    owner.merge_sync(&page.to_string()).unwrap();
    assert!(owner.snapshot(1_797_465_600_000).active);
    let mut changed = page.clone();
    changed["items"][0]["writer"] = json!("other-device");
    assert!(owner.merge_sync(&changed.to_string()).is_err());
    changed = page.clone();
    changed["items"][0]["order"]["valid_from_ms"] = json!(1_797_552_000_000_u64);
    assert!(owner.merge_sync(&changed.to_string()).is_err());
    changed = page.clone();
    changed["items"][0]["order"]["status"] = json!("awaiting_payment");
    owner.merge_sync(&changed.to_string()).unwrap();
    assert!(owner.snapshot(1_797_465_600_000).active);
    assert!(owner.merge_sync(&page.to_string()).is_ok());
}

#[test]
fn a_foreign_prepared_issuer_is_rejected_without_poisoning_a_paid_order() {
    let source_directory = TempDirectory::new("mosh-prepared-source");
    let mut source = open(&source_directory);
    source.save_series("series", &"a".repeat(43)).unwrap();
    source.save_order(&paid_order().to_string(), 0).unwrap();
    let blind = source.prepare_order_issuance("order").unwrap();
    let original = source.export_sync(None).unwrap().unwrap();
    let mut foreign: Value = serde_json::from_str(&original).unwrap();
    foreign["items"][0]["prepared"]["mainnet"]["issuer_key_id"] = json!("b".repeat(64));
    let destination_directory = TempDirectory::new("mosh-prepared-destination");
    let mut destination = open(&destination_directory);
    assert!(destination.merge_sync(&foreign.to_string()).is_err());
    assert!(destination.snapshot(0).orders.is_empty());
    destination.merge_sync(&original).unwrap();
    assert_eq!(destination.prepare_order_issuance("order").unwrap(), blind);
}
