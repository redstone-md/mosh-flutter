use mosh_core::plus::{Certificate, Issuer};
use serde::Deserialize;

#[derive(Deserialize)]
struct Vector {
    public_key: String,
    signature: String,
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
