use super::{proof::IdentityClaim, types::DmTopology};
use crate::{
    device_link::identity::DeviceIdentity, persistence::Persistence,
    signature_verification::test_count, test_temp_directory::TempDirectory,
};
use ed25519_dalek::SigningKey;
use std::sync::Arc;

fn identity() -> (TempDirectory, DeviceIdentity) {
    let dir = TempDirectory::new("mosh-topology-verification");
    let store =
        Arc::new(Persistence::open_with_dek(&dir.path().join("state.redb"), [93; 32]).unwrap());
    let peer = hex::encode(
        SigningKey::generate(&mut rand::rngs::OsRng)
            .verifying_key()
            .as_bytes(),
    );
    let owner = DeviceIdentity::open(store, &peer).unwrap();
    (dir, owner)
}

#[test]
fn unchanged_topology_checks_reuse_signatures_but_check_current_membership() {
    let (_first, first) = identity();
    let (_second, second) = identity();
    let claims = [&first, &second].map(|owner| {
        IdentityClaim::create(
            owner,
            "session",
            owner.key().verifying_key().as_bytes(),
            "User",
        )
        .unwrap()
    });
    let signers: Vec<_> = claims
        .iter()
        .map(|claim| claim.mls_signer.clone())
        .collect();
    let topology = DmTopology {
        own_user_id: first.roster().user_id(),
        clients: claims.into(),
        rosters: vec![first.roster().clone(), second.roster().clone()],
    };
    topology.validate("session", &signers).unwrap();
    let wire = serde_json::to_vec(&topology).unwrap();
    let before = test_count();
    for _ in 0..10 {
        let decoded: DmTopology = serde_json::from_slice(&wire).unwrap();
        decoded.validate("session", &signers).unwrap();
        assert_eq!(serde_json::to_vec(&decoded).unwrap(), wire);
    }
    assert_eq!(
        test_count(),
        before,
        "unchanged topology repeated signatures"
    );
    assert!(topology.validate("another-session", &signers).is_err());
    assert!(topology.validate("session", &signers[..1]).is_err());
    let mut forged = serde_json::to_value(&topology).unwrap();
    forged["clients"][0]["display_name"] = "forged".into();
    let forged: DmTopology = serde_json::from_value(forged).unwrap();
    assert!(forged.validate("session", &signers).is_err());
    assert_current_revocation(&topology, &first, &signers);
}

fn assert_current_revocation(topology: &DmTopology, first: &DeviceIdentity, signers: &[String]) {
    use crate::device_link::types::DeviceDescriptor;
    let sibling = SigningKey::generate(&mut rand::rngs::OsRng);
    let device = DeviceDescriptor::new(&sibling, &hex::encode(sibling.verifying_key().as_bytes()));
    let linked = first.roster().extend(device, &first.key()).unwrap();
    let mut current = topology.clone();
    current.update_roster(linked.clone()).unwrap();
    current.validate("session", signers).unwrap();
    let removed = linked.revoke(&first.device().device_id, &sibling).unwrap();
    current.update_roster(removed).unwrap();
    assert!(current.validate("session", signers).is_err());
}
