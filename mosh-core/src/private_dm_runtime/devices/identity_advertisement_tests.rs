//! Secondary module-boundary checks complement the native recorder scenario.
//! Assert actual control frames, never the advertisement cache's representation.
use super::super::{state_tests::*, *};
use crate::device_link::{identity::DeviceIdentity, types::DeviceDescriptor};
use crate::private_dm_runtime::transport::memory::MemoryNet;
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;

struct OfflineIdentity {
    net: Arc<MemoryNet>,
    runtime: PrivateDmRuntime,
    identity: DeviceIdentity,
    session_id: String,
    start: u64,
    _directory: TempDirectory,
}

impl OfflineIdentity {
    fn new() -> Self {
        let (net, mut runtime, mut contact) = memory_pair();
        let invite = invite(&mut runtime);
        accept(&mut contact, &invite);
        connect(&mut runtime, &mut contact, &invite.session_id);
        let start = now_ms() + LOST_WINDOW_MS;
        runtime.drain_inbound_at(start);
        net.unlist(ALICE_ID, BOB_ID);
        net.endpoint(BOB_ID).drain();
        let directory = TempDirectory::new("mosh-idle-identity");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [67; 32]).unwrap(),
        );
        let identity = DeviceIdentity::open(store, ALICE_ID).unwrap();
        runtime
            .session_mut(&invite.session_id)
            .unwrap()
            .refresh_device_identity(&identity)
            .unwrap();
        Self {
            _directory: directory,
            net,
            runtime,
            identity,
            session_id: invite.session_id,
            start,
        }
    }

    fn advertise(&mut self) -> usize {
        self.runtime
            .session_mut(&self.session_id)
            .unwrap()
            .publish_identity_claim(&self.identity);
        self.net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"DeviceIdentity\""))
            .count()
    }
}

#[test]
fn an_offline_roster_change_bypasses_unchanged_identity_suppression() {
    let mut fixture = OfflineIdentity::new();
    assert_eq!(fixture.advertise(), 1);
    assert_eq!(fixture.advertise(), 0);
    let key = SigningKey::generate(&mut OsRng);
    let device = DeviceDescriptor::new(&key, &hex::encode(key.verifying_key().as_bytes()));
    let roster = fixture
        .identity
        .roster()
        .extend(device, &fixture.identity.key())
        .unwrap();
    fixture.identity.adopt_roster(roster).unwrap();
    assert_eq!(fixture.advertise(), 1);
    assert_eq!(fixture.advertise(), 0);
}

#[test]
fn a_new_mls_epoch_bypasses_offline_identity_suppression() {
    let mut fixture = OfflineIdentity::new();
    assert_eq!(fixture.advertise(), 1);
    assert_eq!(fixture.advertise(), 0);
    let mut joining = MlsSessionCrypto::new("joining").unwrap();
    let package = joining.key_package_bytes().unwrap();
    fixture
        .runtime
        .session_mut(&fixture.session_id)
        .unwrap()
        .crypto
        .add_members(&[&package])
        .unwrap();
    assert_eq!(fixture.advertise(), 1);
    assert_eq!(fixture.advertise(), 0);
}

#[test]
fn failed_identity_sends_retry_after_the_next_presence_probe() {
    for hard_failure in [false, true] {
        let mut fixture = OfflineIdentity::new();
        fixture.net.refuse_publishes(ALICE_ID, !hard_failure);
        fixture.net.fail_publishes(ALICE_ID, hard_failure);
        assert_eq!(fixture.advertise(), 0);
        fixture.net.refuse_publishes(ALICE_ID, false);
        fixture.net.fail_publishes(ALICE_ID, false);
        assert_eq!(
            fixture.advertise(),
            0,
            "failure must not cause a busy retry"
        );
        fixture.runtime.drain_inbound_at(fixture.start + 2000);
        assert_eq!(
            fixture.advertise(),
            1,
            "the next Hello retries the identity"
        );
    }
}
