use super::*;

fn fixture() -> (SigningKey, MlsSessionCrypto, String) {
    let identity = SigningKey::from_bytes(&[4; 32]);
    let mut crypto = MlsSessionCrypto::new("owner").unwrap();
    crypto.create_group().unwrap();
    let uri = super::super::build_invite_uri(
        "mesh",
        "session",
        &crypto.fingerprint(),
        Some(&hex::encode(identity.verifying_key().to_bytes())),
    );
    let mut uri = url::Url::parse(&uri).unwrap();
    uri.query_pairs_mut().append_pair("target", &"b".repeat(64));
    (identity, crypto, uri.into())
}

#[test]
fn owned_invitation_preserves_routing_and_accepts_only_its_moss_owner() {
    let (identity, crypto, uri) = fixture();
    let signed = sign_invite(&uri, &identity, &crypto).unwrap();
    let owner = hex::encode(identity.verifying_key().to_bytes());
    verify_offered_invite(&signed, &owner, &"b".repeat(64)).unwrap();
    let parsed = ParsedInvite::parse(&signed).unwrap();
    assert_eq!(parsed.mesh_id, "mesh");
    assert_eq!(parsed.session_id, "session");
    assert_eq!(parsed.fingerprint, crypto.fingerprint());
    assert_eq!(parsed.peer_moss_id.as_deref(), Some(owner.as_str()));
    assert!(verify_offered_invite(&signed, &"a".repeat(64), &"b".repeat(64)).is_err());
    assert!(verify_offered_invite(&uri, &owner, &"b".repeat(64)).is_err());
    assert!(
        ParsedInvite::parse(&uri).is_ok(),
        "manual legacy invites remain fingerprint-pinned"
    );
}

#[test]
fn changed_invitation_fields_or_stripped_proofs_cannot_be_offered() {
    let (identity, crypto, uri) = fixture();
    let signed = sign_invite(&uri, &identity, &crypto).unwrap();
    for changed in [
        signed.replace("mesh=mesh", "mesh=other"),
        signed.replace("session=session", "session=other"),
        signed.replace(&crypto.fingerprint(), &"A".repeat(32)),
        signed.replace(
            &hex::encode(identity.verifying_key().to_bytes()),
            &"a".repeat(64),
        ),
    ] {
        assert!(ParsedInvite::parse(&changed).is_err());
    }
    let (mut changed, _) = split(&signed).unwrap();
    changed
        .query_pairs_mut()
        .append_pair("peer", "127.0.0.1:1234");
    assert!(verify_offered_invite(
        changed.as_str(),
        &hex::encode(identity.verifying_key().to_bytes()),
        &"b".repeat(64)
    )
    .is_err());
}

#[test]
fn malformed_and_duplicate_ownership_proofs_are_rejected() {
    let (identity, crypto, uri) = fixture();
    let signed = sign_invite(&uri, &identity, &crypto).unwrap();
    let mut duplicate = url::Url::parse(&signed).unwrap();
    duplicate.query_pairs_mut().append_pair("proof", "bad");
    assert!(ParsedInvite::parse(duplicate.as_str()).is_err());
    for value in ["bad!", "e30"] {
        let mut bad = url::Url::parse(&uri).unwrap();
        bad.query_pairs_mut().append_pair("proof", value);
        assert!(ParsedInvite::parse(bad.as_str()).is_err());
    }
}

#[test]
fn an_invitation_cannot_be_signed_with_another_moss_or_dm_identity() {
    let (identity, crypto, uri) = fixture();
    assert!(sign_invite(&uri, &SigningKey::from_bytes(&[5; 32]), &crypto).is_err());
    assert!(sign_invite(&uri, &identity, &MlsSessionCrypto::new("other").unwrap()).is_err());
}
