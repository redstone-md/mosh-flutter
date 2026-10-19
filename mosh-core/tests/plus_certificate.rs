use mosh_core::plus::{Certificate, Issuer};
use serde::Deserialize;

#[derive(Deserialize)]
struct Vector {
    public_key: String,
    signature: String,
}

#[test]
fn production_proof_binds_both_dates_and_cannot_be_used_early_or_as_devnet() {
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let account = "ab".repeat(32);
    let certificate: Certificate = serde_json::from_value(serde_json::json!({
        "account_id": account, "expires_at_ms": vector["expires_at_ms"],
        "signature_b64": vector["signature"], "mainnet": {
            "issuer_key_id": vector["key_id"], "valid_from_ms": vector["valid_from_ms"]
        }
    }))
    .unwrap();
    let issuer = Issuer::mainnet(vector["public_key"].as_str().unwrap()).unwrap();
    let start = vector["valid_from_ms"].as_u64().unwrap();
    issuer.verify(&certificate, &account, start).unwrap();
    issuer.verify_claims(&certificate, &account).unwrap();
    assert!(issuer.verify(&certificate, &account, start - 1).is_err());
    assert!(issuer
        .verify(&certificate, &account, certificate.expires_at_ms)
        .is_err());
    assert!(Issuer::new(vector["public_key"].as_str().unwrap())
        .unwrap()
        .verify(&certificate, &account, start)
        .is_err());
    let mut forged = serde_json::to_value(&certificate).unwrap();
    forged["mainnet"]["valid_from_ms"] = (start - 86_400_000).into();
    assert!(issuer
        .verify_claims(&serde_json::from_value(forged).unwrap(), &account)
        .is_err());
}

#[test]
fn peer_verifies_a_typescript_issued_certificate_for_the_authenticated_account() {
    let vector: Vector =
        serde_json::from_str(include_str!("fixtures/plus-public-vector.json")).unwrap();
    let account = "ab".repeat(32);
    let certificate = Certificate {
        account_id: account.clone(),
        expires_at_ms: 1_800_057_600_000,
        signature_b64: vector.signature,
        mainnet: None,
    };
    let issuer = Issuer::new(&vector.public_key).unwrap();
    issuer
        .verify(&certificate, &account, 1_700_000_000_000)
        .unwrap();
}

#[test]
fn a_certificate_cannot_be_transferred_extended_or_used_after_expiry() {
    let vector: Vector =
        serde_json::from_str(include_str!("fixtures/plus-public-vector.json")).unwrap();
    let issuer = Issuer::new(&vector.public_key).unwrap();
    let account = "ab".repeat(32);
    let certificate = Certificate {
        account_id: account.clone(),
        expires_at_ms: 1_800_057_600_000,
        signature_b64: vector.signature,
        mainnet: None,
    };
    assert!(issuer
        .verify(&certificate, &"cd".repeat(32), 1_700_000_000_000)
        .is_err());
    assert!(issuer
        .verify(&certificate, &account, certificate.expires_at_ms)
        .is_err());
    let mut forged = certificate.clone();
    forged.expires_at_ms += 86_400_000;
    assert!(issuer.verify(&forged, &account, 1_700_000_000_000).is_err());
    forged = certificate;
    forged.account_id = "cd".repeat(32);
    assert!(issuer
        .verify(&forged, &forged.account_id, 1_700_000_000_000)
        .is_err());
}
