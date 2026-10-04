use super::*;
use crate::api::org::workflow_tests::support::Fixture;
use crate::api::org::workflows;
use crate::moss_ffi::{fail_next_test_publish, MOSS_TEST_LOCK};

#[path = "org_join_ordering_tests.rs"]
mod ordering;

fn begin(fixture: &mut Fixture) -> (String, MlsSessionCrypto) {
    let mut admin = MlsSessionCrypto::new(fixture.own_peer()).unwrap();
    admin.create_group().unwrap();
    let uri = build_invite_uri(
        "group-durable",
        "durable-group",
        &admin.fingerprint(),
        &None,
    );
    fixture.deliver_group_offer(&uri);
    let request = fixture.group_join_request(&uri);
    let id = fixture
        .groups
        .prepare_group_restoring(request, None)
        .unwrap();
    (id, admin)
}

fn register(fixture: &mut Fixture, id: &str) {
    workflows::register_prepared_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        id,
    )
    .unwrap();
    fixture.groups.publish_prepared_join(id).unwrap();
    fixture.groups.poll(id).unwrap();
}

fn prepare_welcome(
    fixture: &mut Fixture,
    id: &str,
    admin: &mut MlsSessionCrypto,
) -> MossReceivedMessage {
    let session = fixture.groups.groups.get_mut(id).unwrap();
    let package = session.pending_join_package.as_ref().unwrap();
    let outcome = admin.add_members(&[package.as_slice()]).unwrap();
    let envelope = ControlEnvelope::Welcome {
        group_id: id.into(),
        for_participant_id: session.participant_id.clone(),
        from_fingerprint: admin.fingerprint(),
        welcome_b64: encode(&outcome.welcome_bytes),
        commit_b64: encode(&outcome.commit_bytes),
        tree_b64: encode(&outcome.tree_bytes),
    };
    let context = OrgContext {
        org_pubkey: &fixture.org_key,
        mesh_id: &session.mesh_id,
        channel_kind: &session.control_channel,
    };
    let signed = org_envelope::sign(
        &SigningKey::from_bytes(&[90; 32]),
        &context,
        &serde_json::to_vec(&envelope).unwrap(),
    );
    MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: serde_json::to_vec(&signed).unwrap(),
    }
}

fn welcome(fixture: &mut Fixture, id: &str, admin: &mut MlsSessionCrypto) -> GroupSnapshot {
    inbox::deliver(prepare_welcome(fixture, id, admin));
    fixture.groups.poll(id).unwrap()
}

#[test]
fn a_saved_welcome_retires_the_offer_before_immediate_close_and_stale_org_rewrite() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    register(&mut fixture, &id);
    let snapshot = welcome(&mut fixture, &id, &mut admin);
    assert_eq!(snapshot.member_count, 2);
    assert_eq!(fixture.store.list_groups().unwrap().len(), 1);
    fixture.groups.close(&id).unwrap();
    // This cached session still holds its pending acceptance; a routine record
    // rewrite must merge the durable retirement instead of resurrecting it.
    fixture
        .org
        .link_dm(&fixture.org_key, "unrelated-peer", "unrelated-dm")
        .unwrap();
    fixture.restart();
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .is_empty());
}

#[test]
fn a_volatile_group_welcome_preserves_its_restart_offer() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    register(&mut fixture, &id);
    let fault = fixture.store.refuse_group_snapshot_writes();
    let snapshot = welcome(&mut fixture, &id, &mut admin);
    assert_eq!(snapshot.member_count, 2);
    assert!(fixture.store.list_groups().unwrap().is_empty());
    fixture.restart();
    drop(fault);
    assert_eq!(
        fixture
            .org
            .poll(&fixture.org_key)
            .unwrap()
            .group_offers
            .len(),
        1
    );
    assert!(fixture.groups.list().unwrap().groups.is_empty());
}

#[test]
fn refused_registration_releases_only_the_prepared_group_and_publishes_nothing() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, admin) = begin(&mut fixture);
    fixture.groups.discard_prepared_join(&id);
    let persistence_fault = fixture.store.refuse_org_record_writes();
    let publication_fault = fail_next_test_publish("first KeyPackage must remain unpublished");
    let request = fixture.group_join_request(&build_invite_uri(
        "group-durable",
        &id,
        &admin.fingerprint(),
        &None,
    ));
    let error = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request.clone(),
    )
    .unwrap_err();
    assert_eq!(
        error.kind,
        crate::api::conversation_bridge::ConversationBridgeErrorKind::Persistence
    );
    assert!(!fixture.groups.groups.holds(&id));
    drop(persistence_fault);
    let error = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request.clone(),
    )
    .unwrap_err();
    assert_eq!(
        error.kind,
        crate::api::conversation_bridge::ConversationBridgeErrorKind::Unavailable
    );
    drop(publication_fault);
    assert!(workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .is_ok());
}

fn assert_cached_welcome_recovers(refuse_native_snapshot: bool) {
    let mut fixture = Fixture::new();
    let fault = refuse_native_snapshot.then(|| fixture.store.refuse_group_snapshot_writes());
    let (id, mut admin) = begin(&mut fixture);
    let signer = fixture.groups.group_signer_public(&id).unwrap();
    register(&mut fixture, &id);
    let cached = prepare_welcome(&mut fixture, &id, &mut admin);
    if refuse_native_snapshot {
        inbox::deliver(MossReceivedMessage {
            channel: cached.channel.clone(),
            payload: cached.payload.clone(),
        });
        assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 2);
        assert!(fixture.store.list_groups().unwrap().is_empty());
    }
    if refuse_native_snapshot {
        assert!(fixture.store.get_group_mls_snapshot(&id).is_err());
    } else {
        assert!(fixture.store.get_group_mls_snapshot(&id).unwrap().is_none());
    }
    fixture.restart();
    drop(fault);
    let offer = fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .remove(0);
    let request = fixture.group_join_request(&offer.group_invite_uri);
    workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
    assert_eq!(fixture.groups.group_signer_public(&id).unwrap(), signer);
    inbox::deliver(cached);
    assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 2);
    assert_eq!(fixture.store.list_groups().unwrap().len(), 1);
}

#[test]
fn pending_group_restart_can_accept_the_original_targeted_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    assert_cached_welcome_recovers(false);
}

#[test]
fn group_restart_accepts_original_welcome_when_native_snapshot_writes_were_refused() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    assert_cached_welcome_recovers(true);
}

#[test]
fn an_unsaved_ready_group_resumes_from_its_encrypted_acceptance_snapshot() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_group_snapshot_writes();
    let (id, mut admin) = begin(&mut fixture);
    assert_eq!(welcome(&mut fixture, &id, &mut admin).member_count, 2);
    register(&mut fixture, &id);
    assert!(fixture.store.list_groups().unwrap().is_empty());
    fixture.restart();
    drop(fault);
    let offer = fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .remove(0);
    let request = fixture.group_join_request(&offer.group_invite_uri);
    let recovered = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
    assert_eq!(recovered.member_count, 2);
    assert_eq!(fixture.store.list_groups().unwrap().len(), 1);
}

#[test]
fn registration_of_a_saved_ready_group_keeps_no_cached_recovery_material() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    assert_eq!(welcome(&mut fixture, &id, &mut admin).member_count, 2);
    register(&mut fixture, &id);
    assert!(fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap()
        .is_none());
}

#[test]
fn polling_and_listing_prune_late_durable_recovery_but_read_failure_keeps_it() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    for list in [false, true] {
        let mut fixture = Fixture::new();
        let (id, mut admin) = begin(&mut fixture);
        register(&mut fixture, &id);
        assert_eq!(welcome(&mut fixture, &id, &mut admin).member_count, 2);
        assert!(fixture
            .org
            .offer_recovery(&fixture.org_key, "retryable-offer")
            .unwrap()
            .is_some());
        let fault = fixture.store.refuse_org_record_writes();
        assert!(fixture.org.poll(&fixture.org_key).is_ok());
        assert!(fixture
            .org
            .offer_recovery(&fixture.org_key, "retryable-offer")
            .unwrap()
            .is_some());
        drop(fault);
        if list {
            fixture.org.list();
        } else {
            fixture.org.poll(&fixture.org_key).unwrap();
        }
        assert!(fixture
            .org
            .offer_recovery(&fixture.org_key, "retryable-offer")
            .unwrap()
            .is_none());
    }
}
