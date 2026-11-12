//! Secondary module-boundary checks complement the native recorder scenario.
//! Assert actual control frames, never the advertisement cache's representation.
use super::super::{state_tests::*, *};
use crate::device_link::{identity::DeviceIdentity, types::DeviceDescriptor};
use crate::private_dm_runtime::transport::memory::MemoryNet;
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;

struct Advertiser {
    net: Arc<MemoryNet>,
    runtime: PrivateDmRuntime,
    identity: DeviceIdentity,
    session_id: String,
    start: u64,
    store: Arc<Persistence>,
    _directory: TempDirectory,
}

impl Advertiser {
    /// A session whose contact went offline.
    fn offline() -> Self {
        Self::new(true)
    }

    /// A session connected to its contact.
    fn connected() -> Self {
        Self::new(false)
    }

    fn new(offline: bool) -> Self {
        let (net, mut runtime, mut contact) = memory_pair();
        let invite = invite(&mut runtime);
        accept(&mut contact, &invite);
        connect(&mut runtime, &mut contact, &invite.session_id);
        // Past the lost window the session has heard nothing for too long.
        let start = now_ms() + if offline { LOST_WINDOW_MS } else { 0 };
        runtime.drain_inbound_at(start);
        if offline {
            net.unlist(ALICE_ID, BOB_ID);
        }
        net.endpoint(BOB_ID).drain();
        let directory = TempDirectory::new("mosh-idle-identity");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [67; 32]).unwrap(),
        );
        let identity = DeviceIdentity::open(store.clone(), ALICE_ID).unwrap();
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
            store,
        }
    }

    fn advertise(&mut self) -> usize {
        self.advertise_at(self.start)
    }

    fn advertise_at(&mut self, now: u64) -> usize {
        self.runtime
            .session_mut(&self.session_id)
            .unwrap()
            .publish_identity_claim(&self.identity, now);
        self.net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"DeviceIdentity\""))
            .count()
    }
}

#[test]
fn a_connected_session_advertises_an_unchanged_claim_again_only_with_its_next_hello() {
    let mut fixture = Advertiser::connected();
    assert_eq!(
        fixture.runtime.sessions[fixture.session_id.as_str()].state,
        DmSessionState::Connected
    );
    fixture
        .runtime
        .session_mut(&fixture.session_id)
        .unwrap()
        .attach_persistence(Some(fixture.store.clone()));
    assert_eq!(fixture.advertise(), 1);
    let syncs = fixture.store.syncs();

    assert_eq!(fixture.advertise(), 0);
    assert_eq!(
        fixture.store.syncs(),
        syncs,
        "nothing sealed, nothing saved"
    );

    fixture
        .runtime
        .drain_inbound_at(fixture.start + KEEPALIVE_MS);
    assert_eq!(fixture.advertise(), 1, "the keepalive Hello carries it");
}

#[test]
fn a_connected_session_too_busy_for_a_hello_still_repeats_its_claim() {
    let mut fixture = Advertiser::connected();
    assert_eq!(fixture.advertise(), 1);

    assert_eq!(fixture.advertise_at(fixture.start + KEEPALIVE_MS - 1), 0);
    assert_eq!(fixture.advertise_at(fixture.start + KEEPALIVE_MS), 1);
}

#[test]
fn unchanged_idle_refreshes_and_advertisements_do_not_sign_again() {
    let mut fixture = Advertiser::offline();
    assert_eq!(fixture.advertise(), 1);
    let signed = super::proof::claim_signature_count();
    for _ in 0..10 {
        fixture
            .runtime
            .session_mut(&fixture.session_id)
            .unwrap()
            .refresh_device_identity(&fixture.identity)
            .unwrap();
        assert_eq!(fixture.advertise(), 0);
    }
    assert_eq!(super::proof::claim_signature_count(), signed);
}

#[test]
fn an_offline_roster_change_bypasses_unchanged_identity_suppression() {
    let mut fixture = Advertiser::offline();
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
    let mut fixture = Advertiser::offline();
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
        let mut fixture = Advertiser::offline();
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
