use super::super::invite_ownership::sign_invite;
use super::*;

fn fixture(target: bool) -> (SigningKey, MlsSessionCrypto, String) {
    let identity = SigningKey::from_bytes(&[12; 32]);
    let mut crypto = MlsSessionCrypto::new("Alice").unwrap();
    crypto.create_group().unwrap();
    let mut uri = url::Url::parse(&super::super::build_invite_uri(
        "mesh-0011223344556677",
        "session-8899aabbccddeeff",
        &crypto.fingerprint(),
        Some(&hex::encode(identity.verifying_key().to_bytes())),
    ))
    .unwrap();
    uri.query_pairs_mut()
        .append_pair("token", "invite-abcdef0123456789");
    if target {
        uri.query_pairs_mut().append_pair("target", &"c".repeat(64));
    }
    (identity, crypto, uri.into())
}

#[test]
fn compact_invites_keep_both_signatures_routing_target_and_capability_under_400_chars() {
    for targeted in [false, true] {
        let (identity, crypto, raw) = fixture(targeted);
        let compact = sign_invite(&raw, &identity, &crypto).unwrap();
        assert!(compact.starts_with("mosh://invite/"));
        assert!(compact.len() <= 400, "{}", compact.len());
        let parsed = ParsedInvite::parse(&compact).unwrap();
        assert_eq!(parsed.mesh_id, "mesh-0011223344556677");
        assert_eq!(parsed.session_id, "session-8899aabbccddeeff");
        assert_eq!(parsed.fingerprint, crypto.fingerprint());
        assert_eq!(
            super::super::invite_ownership::invitation_token(&compact)
                .unwrap()
                .as_deref(),
            Some("invite-abcdef0123456789")
        );
        assert_eq!(
            super::super::invite_ownership::target_peer(&compact).unwrap(),
            targeted.then(|| "c".repeat(64))
        );
        assert!(
            super::super::invite_ownership::verify_invite_owner(&compact, &parsed)
                .unwrap()
                .is_some()
        );
    }
}

#[test]
fn every_compact_field_and_signature_is_authenticated() {
    let (identity, crypto, raw) = fixture(true);
    let compact = sign_invite(&raw, &identity, &crypto).unwrap();
    let payload = URL_SAFE_NO_PAD
        .decode(compact.strip_prefix(PREFIX).unwrap())
        .unwrap();
    for index in 0..payload.len() {
        let mut changed = payload.clone();
        changed[index] ^= 1;
        assert!(
            ParsedInvite::parse(&format!("{PREFIX}{}", URL_SAFE_NO_PAD.encode(changed))).is_err(),
            "byte {index}"
        );
    }
    for suffix in ["?target=bad", "#fp=bad", "/", "="] {
        assert!(ParsedInvite::parse(&format!("{compact}{suffix}")).is_err());
    }
}

#[test]
fn extended_legacy_transcripts_remain_signed_and_readable() {
    let (identity, crypto, raw) = fixture(false);
    let mut raw = url::Url::parse(&raw).unwrap();
    raw.query_pairs_mut()
        .append_pair("future", "keep this signed");
    let signed = sign_invite(raw.as_str(), &identity, &crypto).unwrap();
    assert!(signed.contains("proof="));
    assert!(ParsedInvite::parse(&signed).is_ok());
    assert!(
        ParsedInvite::parse(&signed.replace("future=keep+this+signed", "future=changed")).is_err()
    );
}
