use super::proof::{claim_signature_count, IdentityClaim, LocalClaimSigner};
use crate::device_link::identity::DeviceIdentity;
use crate::persistence::Persistence;
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;
use std::sync::Arc;

fn identity() -> (TempDirectory, DeviceIdentity) {
    let directory = TempDirectory::new("mosh-local-claim");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [71; 32]).unwrap(),
    );
    let peer = SigningKey::generate(&mut rand::rngs::OsRng);
    let identity =
        DeviceIdentity::open(store, &hex::encode(peer.verifying_key().as_bytes())).unwrap();
    (directory, identity)
}

#[test]
fn signature_reuse_binds_all_claim_fields_and_preserves_wire_bytes() {
    let (_directory, identity) = identity();
    let first = SigningKey::generate(&mut rand::rngs::OsRng);
    let second = SigningKey::generate(&mut rand::rngs::OsRng);
    let first = first.verifying_key().to_bytes();
    let second = second.verifying_key().to_bytes();
    let mut cached = LocalClaimSigner::default();
    for (session, signer, name) in [
        ("session-a", first, "Alice"),
        ("session-b", first, "Alice"),
        ("session-b", second, "Alice"),
        ("session-b", second, "Renamed"),
        ("session-a", first, "Alice"),
    ] {
        let before = claim_signature_count();
        let claim = cached
            .claim(&identity, identity.roster(), session, &signer, name)
            .unwrap();
        assert_eq!(claim_signature_count(), before + 1);
        claim.verify(session).unwrap();
        let again = cached
            .claim(&identity, identity.roster(), session, &signer, name)
            .unwrap();
        assert_eq!(claim_signature_count(), before + 1);
        let fresh = IdentityClaim::create(&identity, session, &signer, name).unwrap();
        let wire = serde_json::to_vec(&fresh).unwrap();
        assert_eq!(serde_json::to_vec(&claim).unwrap(), wire);
        assert_eq!(serde_json::to_vec(&again).unwrap(), wire);
    }
}

#[test]
fn a_changed_roster_or_device_requires_a_new_signature() {
    let (_directory, mut owner) = identity();
    let (_other_directory, other) = identity();
    let signer = owner.key().verifying_key().to_bytes();
    let mut cached = LocalClaimSigner::default();
    cached
        .claim(&owner, owner.roster(), "session", &signer, "Alice")
        .unwrap();
    let next = owner
        .roster()
        .extend(other.device().clone(), &owner.key())
        .unwrap();
    owner.adopt_roster(next).unwrap();
    let before = claim_signature_count();
    let claim = cached
        .claim(&owner, owner.roster(), "session", &signer, "Alice")
        .unwrap();
    assert_eq!(claim_signature_count(), before + 1);
    claim.verify("session").unwrap();
    let claim = cached
        .claim(&other, other.roster(), "session", &signer, "Alice")
        .unwrap();
    assert_eq!(claim_signature_count(), before + 2);
    claim.verify("session").unwrap();
}

#[test]
fn a_warmed_signature_cannot_bypass_current_device_revocation() {
    let (_directory, root) = identity();
    let (_linked_directory, mut linked) = identity();
    let roster = root
        .roster()
        .extend(linked.device().clone(), &root.key())
        .unwrap();
    let mut record = linked.record.clone();
    record.roster = roster.clone();
    linked.update(record).unwrap();
    let signer = linked.key().verifying_key().to_bytes();
    let mut cached = LocalClaimSigner::default();
    cached
        .claim(&linked, &roster, "session", &signer, "Alice")
        .unwrap();
    let removed = roster
        .revoke(&linked.device().device_id, &root.key())
        .unwrap();
    linked.adopt_roster(removed).unwrap();
    let signed = claim_signature_count();
    assert!(cached
        .claim(&linked, &roster, "session", &signer, "Alice")
        .is_err());
    assert_eq!(claim_signature_count(), signed);
    assert!(cached
        .claim(&linked, root.roster(), "session", &signer, "Alice")
        .is_err());
}
