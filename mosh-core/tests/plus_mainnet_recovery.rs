#[path = "support/temp_directory.rs"]
mod temp_directory;

use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::{
    PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair,
    PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey,
};
use ed25519_dalek::{Signature, VerifyingKey};
use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use std::sync::Arc;
use temp_directory::TempDirectory;

#[test]
fn recovery_saves_its_destination_key_and_blinding_state_before_network_requests() {
    let directory = TempDirectory::new("mosh-mainnet-recovery");
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
            "cd".repeat(32),
            vector["public_key"].as_str().unwrap(),
            "founder",
        )
        .unwrap()
    };
    let start = 1_797_465_600_000;
    let end = 1_800_057_600_000;
    let mut owner = open();
    owner
        .reconcile_plus_roster("roster", "founder", &["founder".into()])
        .unwrap();
    let series = owner.prepare_series().unwrap();
    owner.confirm_series_registered(&series.id).unwrap();
    let session = owner.prepare_recovery(start).unwrap();
    owner
        .save_recovery_status(
            &status(
                &session.id,
                &session.code,
                vector["key_id"].as_str().unwrap(),
                start,
                end,
            ),
            start,
        )
        .unwrap();
    let request = owner.prepare_recovery_issuance("recovered").unwrap();
    let message = format!(
        "mosh-plus-recovery-issue-v1\0{}\0recovered\0{}",
        session.id, request.blinded_message_b64
    );
    let public: [u8; 32] = STANDARD
        .decode(&session.public_key_b64)
        .unwrap()
        .try_into()
        .unwrap();
    VerifyingKey::from_bytes(&public)
        .unwrap()
        .verify_strict(
            message.as_bytes(),
            &Signature::from_slice(&STANDARD.decode(&request.destination_signature_b64).unwrap())
                .unwrap(),
        )
        .unwrap();
    drop(owner);
    let mut owner = open();
    assert_eq!(owner.prepare_recovery(start).unwrap().id, session.id);
    assert_eq!(
        owner
            .prepare_recovery_issuance("recovered")
            .unwrap()
            .blinded_message_b64,
        request.blinded_message_b64
    );
    let metadata = format!(
        "mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{}\0{start}\0{end}",
        vector["key_id"].as_str().unwrap()
    );
    let derived = issuer
        .derive_key_pair_for_metadata(metadata.as_bytes())
        .unwrap();
    let signature = derived
        .sk
        .blind_sign(STANDARD.decode(request.blinded_message_b64).unwrap())
        .unwrap();
    owner
        .complete_order_issuance("recovered", &STANDARD.encode(signature.0), start)
        .unwrap();
    assert!(owner.snapshot(start).active);
    assert_eq!(owner.snapshot(start).expires_at_ms, Some(end));
}

fn status(id: &str, code: &str, issuer: &str, start: u64, end: u64) -> String {
    serde_json::json!({ "id":id, "code":code, "url":format!("https://billing.example/recover/{id}"),
        "expires_at_ms":start+900_000, "orders":[{ "id":"recovered", "network":"solana-mainnet",
            "product":"mosh-plus-supporter-30d", "issuer_key_id":issuer, "series_id":"original-series",
            "asset":"USDC", "token_decimals":6, "mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "recipient":"11111111111111111111111111111111", "amount_atomic":"5000000",
            "reference":"So11111111111111111111111111111111111111112", "status":"issued",
            "valid_from_ms":start,"expires_at_ms":end,
            "payment_uri":"solana:11111111111111111111111111111111?amount=5&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&reference=So11111111111111111111111111111111111111112" }]
    }).to_string()
}
