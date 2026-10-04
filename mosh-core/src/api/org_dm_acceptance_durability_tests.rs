use super::*;
use crate::conversation::{decode, encode};
use crate::mls_crypto::MlsSessionCrypto;
use crate::private_dm_runtime::transport::DmTransport;
use crate::private_dm_runtime::{DmSessionState, PeerTransport};
use serde_json::json;

fn retry(fixture: &mut Fixture, invite: &str) -> Result<SessionSnapshot, ConversationBridgeError> {
    workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(invite),
    )
}

fn initial_offer(fixture: &mut Fixture) -> (String, MlsSessionCrypto) {
    let mut inviter = MlsSessionCrypto::new("Bob").unwrap();
    inviter.create_group().unwrap();
    let invite = format!(
        "mosh://invite?mesh=dm-durable&session=durable-dm#fp={}",
        inviter.fingerprint()
    );
    fixture.deliver_dm_offer(&invite);
    (invite, inviter)
}

fn accept(fixture: &mut Fixture) -> (String, MlsSessionCrypto) {
    let (invite, inviter) = initial_offer(fixture);
    let snapshot = retry(fixture, &invite).unwrap();
    (snapshot.session_id, inviter)
}

fn prepare_welcome(
    fixture: &mut Fixture,
    id: &str,
    inviter: &mut MlsSessionCrypto,
) -> serde_json::Value {
    let peer_id = crate::org_signing::peer_id_hex(&fixture.member);
    let endpoint = fixture.net.endpoint(&peer_id);
    let package = endpoint
        .drain()
        .into_iter()
        .map(|frame| serde_json::from_slice::<serde_json::Value>(&frame.payload).unwrap())
        .find(|frame| frame["type"] == "KeyPackage")
        .unwrap();
    let key_package = decode(package["key_package_b64"].as_str().unwrap()).unwrap();
    welcome_for_package(fixture, id, inviter, &key_package)
}

fn welcome_for_package(
    fixture: &Fixture,
    id: &str,
    inviter: &mut MlsSessionCrypto,
    key_package: &[u8],
) -> serde_json::Value {
    let (welcome, tree) = inviter.add_peer(key_package).unwrap();
    json!({
        "type": "Welcome", "session_id": id, "participant_id": "inviter",
        "from_device": "Bob", "welcome_b64": encode(&welcome),
        "ratchet_tree_b64": encode(&tree),
        "moss_peer_id": crate::org_signing::peer_id_hex(&fixture.member),
    })
}

fn deliver_welcome(fixture: &mut Fixture, id: &str, envelope: &serde_json::Value) {
    let peer_id = crate::org_signing::peer_id_hex(&fixture.member);
    let endpoint = fixture.net.endpoint(&peer_id);
    fixture
        .net
        .link(&peer_id, fixture.own_peer(), PeerTransport::Direct);
    endpoint
        .publish(
            "dm-durable",
            &format!("mls-control/{id}"),
            &serde_json::to_vec(envelope).unwrap(),
        )
        .unwrap();
}

fn welcome(fixture: &mut Fixture, id: &str, inviter: &mut MlsSessionCrypto) {
    let envelope = prepare_welcome(fixture, id, inviter);
    deliver_welcome(fixture, id, &envelope);
}

#[test]
fn durable_welcome_retires_offer_even_when_closed_before_an_org_poll() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut inviter) = accept(&mut fixture);
    welcome(&mut fixture, &id, &mut inviter);
    fixture.dm.poll_session(&id).unwrap();
    assert!(!fixture.store.list_sessions().unwrap().is_empty());
    fixture.dm.close_session(&id).unwrap();
    fixture.restart();
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .dm_offers
        .is_empty());
}

#[test]
fn a_volatile_welcome_does_not_hide_the_offer_after_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut inviter) = accept(&mut fixture);
    let fault = fixture.store.refuse_dm_snapshot_writes();
    welcome(&mut fixture, &id, &mut inviter);
    let snapshot = fixture.dm.poll_session(&id).unwrap();
    assert_ne!(snapshot.state, DmSessionState::Pending);
    assert!(fixture.store.list_sessions().unwrap().is_empty());
    fixture.restart();
    drop(fault);
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_offers.len(),
        1
    );
    assert!(fixture.dm.list_sessions().unwrap().sessions.is_empty());
}

fn assert_cached_welcome_recovers(refuse_snapshot: bool) {
    let mut fixture = Fixture::new();
    let fault = refuse_snapshot.then(|| fixture.store.refuse_dm_snapshot_writes());
    let (id, mut inviter) = accept(&mut fixture);
    let signer = fixture.dm.session_signer_public(&id).unwrap();
    let cached_welcome = prepare_welcome(&mut fixture, &id, &mut inviter);
    if refuse_snapshot {
        assert!(fixture.store.get_mls_snapshot(&id).is_err());
    }
    fixture.restart();
    drop(fault);
    let offer = fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .dm_offers
        .remove(0);
    retry(&mut fixture, &offer.invite_uri).unwrap();
    assert_eq!(fixture.dm.session_signer_public(&id).unwrap(), signer);
    deliver_welcome(&mut fixture, &id, &cached_welcome);
    let snapshot = fixture.dm.poll_session(&id).unwrap();
    assert_ne!(snapshot.state, DmSessionState::Pending);
    assert_eq!(fixture.store.list_sessions().unwrap().len(), 1);
}

#[test]
fn pending_dm_restart_can_accept_the_inviter_cached_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    assert_cached_welcome_recovers(false);
}

#[test]
fn pending_dm_restart_accepts_cached_welcome_when_initial_snapshot_was_refused() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    assert_cached_welcome_recovers(true);
}

#[test]
fn refused_retry_registration_keeps_the_original_crypto_backup_and_offer() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut inviter) = accept(&mut fixture);
    let cached = prepare_welcome(&mut fixture, &id, &mut inviter);
    fixture.restart();
    let (_, before) = fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap()
        .unwrap();
    let offer = fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .dm_offers
        .remove(0);
    deliver_welcome(&mut fixture, &id, &cached);
    let fault = fixture.store.refuse_org_record_writes();
    let result = retry(&mut fixture, &offer.invite_uri);
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::Persistence
    );
    let (_, after) = fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap()
        .unwrap();
    assert!(before.provider_snapshot == after.provider_snapshot);
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_offers.len(),
        1
    );
    drop(fault);
    let resumed = retry(&mut fixture, &offer.invite_uri).unwrap();
    // Registration failure must leave the cached Welcome unconsumed. The retry
    // completes from that same frame without any inviter redelivery.
    assert_ne!(resumed.state, DmSessionState::Pending);
    assert_eq!(fixture.store.list_sessions().unwrap().len(), 1);
    assert_ne!(
        fixture.dm.poll_session(&id).unwrap().state,
        DmSessionState::Pending
    );
}

#[test]
fn refused_publication_keeps_the_original_key_package_recoverable_after_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (invite, mut inviter) = initial_offer(&mut fixture);
    fixture.net.fail_publishes(fixture.own_peer(), true);
    assert_eq!(
        retry(&mut fixture, &invite).unwrap_err().kind,
        ConversationBridgeErrorKind::Unavailable
    );
    let (_, recovery) = fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap()
        .unwrap();
    assert!(fixture.dm.list_sessions().unwrap().sessions.is_empty());
    let cached = welcome_for_package(
        &fixture,
        "durable-dm",
        &mut inviter,
        recovery.key_package.as_deref().unwrap(),
    );
    fixture.net.fail_publishes(fixture.own_peer(), false);
    fixture.restart();
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_offers.len(),
        1
    );
    deliver_welcome(&mut fixture, "durable-dm", &cached);
    assert_ne!(
        retry(&mut fixture, &invite).unwrap().state,
        DmSessionState::Pending
    );
    assert_eq!(fixture.store.list_sessions().unwrap().len(), 1);
}
