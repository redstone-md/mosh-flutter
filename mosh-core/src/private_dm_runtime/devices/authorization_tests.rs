//! Secondary proof of the signed admission contract with real keys and redb.
use super::{
    admission::{verify_authorizer, verify_request},
    proof::{DevicePacket, IdentityClaim},
    types::*,
};
use crate::{
    device_link::identity::DeviceIdentity, mls_crypto::MlsSessionCrypto, persistence::Persistence,
};
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use std::{path::PathBuf, sync::Arc};

struct StoreDir(PathBuf);
impl Drop for StoreDir {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

fn identity() -> (StoreDir, DeviceIdentity) {
    let dir = std::env::temp_dir().join(format!("mosh-dm-authorization-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&dir).unwrap();
    let store = Arc::new(Persistence::open_with_dek(&dir.join("history.redb"), [29; 32]).unwrap());
    let peer_key = SigningKey::generate(&mut OsRng);
    let identity =
        DeviceIdentity::open(store, &hex::encode(peer_key.verifying_key().as_bytes())).unwrap();
    (StoreDir(dir), identity)
}

fn claim(identity: &DeviceIdentity, crypto: &MlsSessionCrypto) -> IdentityClaim {
    IdentityClaim::create(identity, "existing-dm", &crypto.signer_public(), "Alice").unwrap()
}

#[test]
fn identity_claim_binds_session_device_signer_name_and_roster() {
    let (_dir, identity) = identity();
    let crypto = MlsSessionCrypto::new(&identity.device().device_id).unwrap();
    let original = claim(&identity, &crypto);
    original.verify("existing-dm").unwrap();
    assert!(original.verify("another-dm").is_err());
    let mut changed = original.clone();
    changed.display_name = "Mallory".into();
    assert!(changed.verify("existing-dm").is_err());
    let mut changed = original.clone();
    changed.mls_signer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    assert!(changed.verify("existing-dm").is_err());
    let (_other_dir, other) = self::identity();
    let mut changed = original;
    changed.roster = other.roster().clone();
    assert!(changed.verify("existing-dm").is_err());
}

#[test]
fn admission_packets_reject_changed_content_recipient_and_missing_signatures() {
    let (_dir, identity) = identity();
    let message = DeviceMessage::Ack {
        session_id: "existing-dm".into(),
        request_id: "join-1".into(),
        epoch: 2,
    };
    let bytes = DevicePacket::seal(&identity, "receiver", message).unwrap();
    DevicePacket::open(&bytes, "receiver").unwrap();
    assert!(DevicePacket::open(&bytes, "other receiver").is_err());
    let mut changed: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    changed["message"]["Ack"]["epoch"] = serde_json::json!(3);
    assert!(DevicePacket::open(&serde_json::to_vec(&changed).unwrap(), "receiver").is_err());
    changed["signature"] = serde_json::json!("");
    assert!(DevicePacket::open(&serde_json::to_vec(&changed).unwrap(), "receiver").is_err());
    assert!(DevicePacket::open(b"invalid", "receiver").is_err());
    assert!(DevicePacket::open(&vec![0; super::MAX_PACKET_BYTES + 1], "receiver").is_err());
}

#[test]
fn signed_key_package_must_use_the_authorized_device_identity_and_signer() {
    let (_dir, identity) = identity();
    let mut crypto = MlsSessionCrypto::new(&identity.device().device_id).unwrap();
    let request = JoinRequest {
        request_id: "join-1".into(),
        claim: claim(&identity, &crypto),
        key_package: crypto.key_package_bytes().unwrap(),
    };
    verify_request(&crypto, &request).unwrap();
    let mut other = MlsSessionCrypto::new(&identity.device().device_id).unwrap();
    let mut changed = request.clone();
    changed.key_package = other.key_package_bytes().unwrap();
    assert!(verify_request(&crypto, &changed).is_err());
    let mut wrong_identity = MlsSessionCrypto::new("a display name is not a device id").unwrap();
    changed.claim = claim(&identity, &wrong_identity);
    changed.key_package = wrong_identity.key_package_bytes().unwrap();
    assert!(verify_request(&crypto, &changed).is_err());
    changed.key_package = vec![0; 10];
    assert!(verify_request(&crypto, &changed).is_err());
}

#[test]
fn a_valid_self_signed_outsider_cannot_authorize_dm_admission() {
    let (_root_dir, root) = identity();
    let (_contact_dir, contact) = identity();
    let (_outsider_dir, outsider) = identity();
    let root_crypto = MlsSessionCrypto::new(&root.device().device_id).unwrap();
    let contact_crypto = MlsSessionCrypto::new(&contact.device().device_id).unwrap();
    let mut outsider_crypto = MlsSessionCrypto::new(&outsider.device().device_id).unwrap();
    let membership = DeviceMembership {
        topology: DmTopology {
            own_user_id: root.roster().user_id(),
            clients: vec![claim(&root, &root_crypto), claim(&contact, &contact_crypto)],
            rosters: vec![root.roster().clone(), contact.roster().clone()],
        },
        joining: None,
        delivery: None,
        receipt_targets: Default::default(),
        delivered_ids: Vec::new(),
        history_import: None,
        history_exports: Vec::new(),
        recovery: None,
        recovery_exports: Vec::new(),
        epoch_records: Vec::new(),
        removals: Vec::new(),
        revoked: false,
        pending_rosters: Vec::new(),
    };
    let admission = Admission {
        recovery_authorization: None,
        request: JoinRequest {
            request_id: "outsider-join".into(),
            claim: claim(&outsider, &outsider_crypto),
            key_package: outsider_crypto.key_package_bytes().unwrap(),
        },
        commit: Vec::new(),
        welcome: Vec::new(),
        tree: Vec::new(),
        group_id: Vec::new(),
        epoch: 2,
        topology: membership.topology.clone(),
    };
    // The outsider owns its genuine signing key; this is not a malformed signature.
    verify_request(&root_crypto, &admission.request).unwrap();
    assert!(verify_authorizer(
        &membership,
        outsider.device(),
        outsider.roster(),
        &admission
    )
    .is_err());
    assert!(verify_authorizer(&membership, root.device(), root.roster(), &admission).is_err());
    assert_eq!(membership.topology.clients.len(), 2);
}

#[test]
fn pinned_roster_rejects_rollback_and_third_user_and_checks_exact_leaf_set() {
    let (_root_dir, root) = identity();
    let (_linked_dir, linked) = identity();
    let (_contact_dir, contact) = identity();
    let root_crypto = MlsSessionCrypto::new(&root.device().device_id).unwrap();
    let contact_crypto = MlsSessionCrypto::new(&contact.device().device_id).unwrap();
    let mut topology = DmTopology {
        own_user_id: root.roster().user_id(),
        clients: vec![claim(&root, &root_crypto), claim(&contact, &contact_crypto)],
        rosters: vec![root.roster().clone(), contact.roster().clone()],
    };
    let signers = vec![
        hex::encode(root_crypto.signer_public()),
        hex::encode(contact_crypto.signer_public()),
    ];
    topology.validate("existing-dm", &signers).unwrap();
    let extended = root
        .roster()
        .extend(linked.device().clone(), &root.key())
        .unwrap();
    topology.update_roster(extended.clone()).unwrap();
    assert!(topology.update_roster(root.roster().clone()).is_err());
    assert!(topology.update_roster(linked.roster().clone()).is_err());
    assert_eq!(
        topology
            .roster(&root.roster().user_id())
            .unwrap()
            .digest()
            .unwrap(),
        extended.digest().unwrap()
    );
    assert!(topology.validate("another-dm", &signers).is_err());
    assert!(topology.validate("existing-dm", &signers[..1]).is_err());
}

#[test]
fn simultaneous_identity_initializers_keep_one_stored_identity() {
    let dir = std::env::temp_dir().join(format!("mosh-dm-init-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&dir).unwrap();
    let _guard = StoreDir(dir.clone());
    let store = Arc::new(Persistence::open_with_dek(&dir.join("history.redb"), [29; 32]).unwrap());
    let peer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    let identities = std::thread::scope(|scope| {
        let first = scope.spawn(|| DeviceIdentity::open(store.clone(), &peer).unwrap());
        let second = scope.spawn(|| DeviceIdentity::open(store.clone(), &peer).unwrap());
        (first.join().unwrap(), second.join().unwrap())
    });
    assert_eq!(identities.0.device(), identities.1.device());
    assert_eq!(
        DeviceIdentity::open(store.clone(), &peer).unwrap().device(),
        identities.0.device()
    );
}
