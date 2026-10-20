use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::{
    pbrsa::PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair,
    pbrsa::PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey, DefaultRng,
};
use mosh_core::plus::{Certificate, Issuer, MainnetClaims};
use serde::Deserialize;

#[derive(Deserialize)]
struct Vector {
    public_key: String,
    signature: String,
}

#[test]
fn production_peers_enforce_the_product_period_even_with_a_valid_issuer_signature() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/ietf-draft02-public-test-key.json")).unwrap();
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let sk = SecretKey::from_der(
        &STANDARD
            .decode(fixture["pkcs8_b64"].as_str().unwrap())
            .unwrap(),
    )
    .unwrap();
    let key = KeyPair {
        pk: sk.public_key().unwrap(),
        sk,
    };
    let verifier = Issuer::mainnet(vector["public_key"].as_str().unwrap()).unwrap();
    let account = "ab".repeat(32);
    let from = vector["valid_from_ms"].as_u64().unwrap();
    let key_id = vector["key_id"].as_str().unwrap();
    for days in [29, 30, 31, 32] {
        let certificate = signed_period(&key, &account, key_id, from, from + days * 86_400_000);
        assert_eq!(
            verifier.verify(&certificate, &account, from).is_ok(),
            (30..=31).contains(&days)
        );
    }
}

fn signed_period(key: &KeyPair, account: &str, key_id: &str, from: u64, until: u64) -> Certificate {
    let metadata =
        format!("mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{key_id}\0{from}\0{until}");
    let message = format!("mosh-plus-subject-v1\0{account}");
    let derived = key
        .derive_key_pair_for_metadata(metadata.as_bytes())
        .unwrap();
    let blind = derived
        .pk
        .blind(
            &mut DefaultRng,
            message.as_bytes(),
            Some(metadata.as_bytes()),
        )
        .unwrap();
    let reply = derived.sk.blind_sign(&blind.blind_message.0).unwrap();
    let signature = derived
        .pk
        .finalize(
            &reply,
            &blind,
            message.as_bytes(),
            Some(metadata.as_bytes()),
        )
        .unwrap();
    Certificate {
        account_id: account.into(),
        expires_at_ms: until,
        signature_b64: STANDARD.encode(signature.0),
        mainnet: Some(MainnetClaims {
            issuer_key_id: key_id.into(),
            valid_from_ms: from,
        }),
    }
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
