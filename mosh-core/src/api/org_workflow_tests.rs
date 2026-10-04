use super::*;
use crate::moss_ffi::{fail_next_test_publish, MOSS_TEST_LOCK};

#[path = "org_workflow_test_support.rs"]
pub(crate) mod support;
use support::Fixture;

#[path = "org_group_acceptance_tests.rs"]
mod group_acceptance;

#[path = "org_dm_acceptance_durability_tests.rs"]
mod dm_durability;

#[test]
fn malformed_dm_invite_never_exposes_an_org_offer_or_creates_a_session() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.deliver_dm_offer("malformed invite");
    let result = workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request("malformed invite"),
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::InvalidInput
    );
    let org = fixture.org.poll(&fixture.org_key).unwrap();
    assert!(org.dm_offers.is_empty());
    assert!(org.dm_links.is_empty());
    assert!(fixture.dm.list_sessions().unwrap().sessions.is_empty());
}

#[test]
fn hard_dm_admission_failure_retains_offer_then_successful_retry_links_once() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let uri = fixture.dm_invite();
    fixture.deliver_dm_offer(&uri);
    fixture.net.fail_publishes(fixture.own_peer(), true);
    let result = workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::Unavailable
    );
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_offers.len(),
        1
    );
    fixture.net.fail_publishes(fixture.own_peer(), false);
    let session = workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    )
    .unwrap();
    let org = fixture.org.poll(&fixture.org_key).unwrap();
    assert!(org.dm_offers.is_empty());
    assert_eq!(org.dm_links.len(), 1);
    assert_eq!(
        org.dm_links[0].session_id.as_deref(),
        Some(session.session_id.as_str())
    );
}

#[test]
fn refused_org_completion_preserves_offer_and_rolls_back_only_the_new_dm() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let uri = fixture.dm_invite();
    fixture.deliver_dm_offer(&uri);
    let fault = fixture.store.refuse_org_record_writes();
    let result = workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::Persistence
    );
    let org = fixture.org.poll(&fixture.org_key).unwrap();
    assert_eq!(org.dm_offers.len(), 1);
    assert!(org.dm_links.is_empty());
    assert!(fixture.dm.list_sessions().unwrap().sessions.is_empty());
    assert_eq!(
        fixture.published_dm_frames(),
        0,
        "registration refusal must publish no KeyPackage"
    );
    drop(fault);
    workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    )
    .unwrap();
}

#[test]
fn invalid_org_or_roster_target_never_creates_a_group() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    for org in ["not-joined", fixture.org_key.as_str()] {
        let request = fixture.group_request();
        let result = workflows::create_and_offer_group(
            &mut fixture.org,
            &mut fixture.groups,
            org,
            &["unknown-peer".into()],
            request,
        );
        assert!(result.is_err());
        assert!(fixture.groups.list().unwrap().groups.is_empty());
        assert!(fixture.store.list_groups().unwrap().is_empty());
    }
}

#[test]
fn failed_group_offer_returns_created_group_and_existing_reoffer_still_works() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let request = fixture.group_request();
    let target = crate::org_signing::peer_id_hex(&fixture.member);
    let fault = fail_next_test_publish("one org group offer failed");
    let created = workflows::create_and_offer_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        std::slice::from_ref(&target),
        request,
    )
    .unwrap();
    drop(fault);
    let group = fixture.groups.poll(&created.group_id).unwrap();
    assert_eq!(
        group.invite_uri.as_deref(),
        Some(created.invite_uri.as_str())
    );
    assert_eq!(fixture.groups.list().unwrap().groups.len(), 1);
    fixture
        .org
        .send_group_offer(
            &fixture.org_key,
            &target,
            &created.invite_uri,
            created.label,
        )
        .unwrap();
}

#[test]
fn group_offers_attempt_every_recipient_after_a_hard_publication_failure() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let request = fixture.group_request();
    let created = fixture.groups.create_group(request).unwrap();
    let targets = vec![
        crate::org_signing::peer_id_hex(&fixture.member),
        fixture.other_peer(),
    ];
    let mut attempts = Vec::new();
    let _fault = fail_next_test_publish("first invitation refused");
    workflows::offer_created_group(&fixture.org_key, &targets, |target| {
        attempts.push(target.to_string());
        fixture
            .org
            .send_group_offer(&fixture.org_key, target, &created.invite_uri, None)
    });
    assert_eq!(attempts, targets);
}

#[test]
fn accepted_pending_dm_offer_is_recoverable_after_restart_without_redelivery() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let uri = fixture.dm_invite();
    fixture.deliver_dm_offer(&uri);
    let snapshot = workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    )
    .unwrap();
    assert_eq!(
        snapshot.state,
        crate::private_dm_runtime::DmSessionState::Pending
    );
    assert!(fixture.store.list_sessions().unwrap().is_empty());
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .dm_offers
        .is_empty());
    fixture.restart();
    let snapshot = fixture.org.poll(&fixture.org_key).unwrap();
    assert_eq!(snapshot.dm_offers.len(), 1);
    assert_eq!(snapshot.dm_offers[0].invite_uri, uri);
    fixture.deliver_dm_offer(&uri);
    assert_eq!(
        fixture.org.poll(&fixture.org_key).unwrap().dm_offers.len(),
        1
    );
    workflows::accept_and_link_dm(
        &mut fixture.org,
        &mut fixture.dm,
        &fixture.org_key,
        "retryable-offer",
        Fixture::dm_request(&uri),
    )
    .unwrap();
}
