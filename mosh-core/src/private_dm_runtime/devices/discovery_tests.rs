use super::super::{state_tests::*, *};
use super::proof::IdentityClaim;
use crate::device_link::identity::{DeviceIdentity, LocalIdentity};
use crate::private_dm_runtime::transport::memory::MemoryNet;
use crate::test_temp_directory::TempDirectory;

fn identity(peer: &str) -> (TempDirectory, DeviceIdentity) {
    let dir = TempDirectory::new("mosh-discovery-identity");
    let store =
        Arc::new(Persistence::open_with_dek(&dir.path().join("history.redb"), [61; 32]).unwrap());
    let identity = DeviceIdentity::open(store, peer).unwrap();
    (dir, identity)
}

struct KnownDm {
    net: Arc<MemoryNet>,
    alice: PrivateDmRuntime,
    invite: InviteCreated,
    identity: DeviceIdentity,
    _dirs: [TempDirectory; 2],
}

impl KnownDm {
    fn new() -> Self {
        let (net, mut alice, mut bob) = memory_pair();
        let invite = invite(&mut alice);
        accept(&mut bob, &invite);
        connect(&mut alice, &mut bob, &invite.session_id);
        assert_eq!(net.room_discovery(ALICE_ID, &invite.mesh_id), Some(vec![]));
        let (alice_dir, alice_identity) = identity(ALICE_ID);
        let (bob_dir, bob_identity) = identity(BOB_ID);
        for (runtime, identity) in [(&mut alice, &alice_identity), (&mut bob, &bob_identity)] {
            let session = runtime.session_mut(&invite.session_id).unwrap();
            session.refresh_device_identity(identity).unwrap();
            session.publish_identity_claim(identity);
        }
        for _ in 0..3 {
            alice.poll_session(&invite.session_id).unwrap();
            bob.poll_session(&invite.session_id).unwrap();
        }
        assert_eq!(
            net.room_discovery(BOB_ID, &invite.mesh_id),
            Some(vec![ALICE_ID.to_string()])
        );
        Self {
            net,
            alice,
            invite,
            identity: alice_identity,
            _dirs: [alice_dir, bob_dir],
        }
    }

    fn session(&mut self) -> &mut PrivateDmSession {
        self.alice.session_mut(&self.invite.session_id).unwrap()
    }

    fn recipients(&mut self) -> Vec<String> {
        self.alice.poll_session(&self.invite.session_id).unwrap();
        self.net
            .room_discovery(ALICE_ID, &self.invite.mesh_id)
            .unwrap()
    }

    fn sibling(&mut self) -> (TempDirectory, DeviceIdentity) {
        let (dir, mut sibling) = identity(&"cc".repeat(32));
        let roster = self
            .identity
            .roster()
            .extend(sibling.device().clone(), &self.identity.key())
            .unwrap();
        self.identity.adopt_roster(roster.clone()).unwrap();
        // Pre-admitted fixture: preserve the sibling's own key and install the
        // genuine authorizer-signed roster. Native flows cover the pairing UI.
        let raw = sibling.persistence().get_device_link().unwrap().unwrap();
        let mut record: LocalIdentity = serde_json::from_slice(&raw).unwrap();
        record.roster = roster;
        sibling.update(record).unwrap();
        (dir, sibling)
    }
}

#[test]
fn complete_authenticated_dm_uses_known_recipients_and_unknown_member_restores_automatic() {
    let mut dm = KnownDm::new();
    assert_eq!(dm.recipients(), vec![BOB_ID.to_string()]);
    let mut new_device = MlsSessionCrypto::new("new-device").unwrap();
    let package = new_device.key_package_bytes().unwrap();
    dm.session().crypto.add_members(&[&package]).unwrap();
    assert!(
        dm.recipients().is_empty(),
        "missing authenticated route must restore discovery"
    );
}

#[test]
fn authenticated_device_admission_expands_recipients_and_removal_contracts_them() {
    let mut dm = KnownDm::new();
    let (_dir, sibling) = dm.sibling();
    let mut crypto = MlsSessionCrypto::new("sibling").unwrap();
    let package = crypto.key_package_bytes().unwrap();
    dm.session().crypto.add_members(&[&package]).unwrap();
    assert!(dm.recipients().is_empty());
    let claim = IdentityClaim::create(
        &sibling,
        &dm.invite.session_id,
        &crypto.signer_public(),
        "Sibling",
    )
    .unwrap();
    dm.session()
        .membership
        .as_mut()
        .unwrap()
        .topology
        .add_client(claim)
        .unwrap();
    assert_eq!(dm.recipients(), vec![BOB_ID.to_string(), "cc".repeat(32)]);
    let signer = hex::encode(crypto.signer_public());
    let roster = dm
        .identity
        .roster()
        .revoke(&sibling.device().device_id, &dm.identity.key())
        .unwrap();
    let session = dm.session();
    session.crypto.remove_member_by_signer(&signer).unwrap();
    let membership = session.membership.as_mut().unwrap();
    membership
        .topology
        .clients
        .retain(|client| client.mls_signer != signer);
    membership.topology.update_roster(roster).unwrap();
    assert_eq!(dm.recipients(), vec![BOB_ID.to_string()]);
}

#[test]
fn revoked_local_membership_restores_automatic_even_when_protocol_service_stops() {
    let mut dm = KnownDm::new();
    assert_eq!(dm.recipients(), vec![BOB_ID.to_string()]);
    dm.session().membership.as_mut().unwrap().revoked = true;
    assert!(dm.recipients().is_empty());
}
