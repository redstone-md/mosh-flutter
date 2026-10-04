use super::*;
use crate::api::conversation_bridge::{ConversationBridgeError, ConversationBridgeErrorKind};

fn retry(fixture: &mut Fixture, invite: &str) -> Result<GroupSnapshot, ConversationBridgeError> {
    let request = fixture.group_join_request(invite);
    workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
}

fn retry_uri(fixture: &mut Fixture) -> String {
    fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .remove(0)
        .group_invite_uri
}

#[test]
fn refused_recovered_registration_does_not_consume_the_queued_original_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    register(&mut fixture, &id);
    let cached = prepare_welcome(&mut fixture, &id, &mut admin);
    fixture.restart();
    let invite = retry_uri(&mut fixture);
    inbox::deliver(cached);
    let fault = fixture.store.refuse_org_record_writes();
    assert_eq!(
        retry(&mut fixture, &invite).unwrap_err().kind,
        ConversationBridgeErrorKind::Persistence
    );
    assert!(!fixture.groups.groups.holds(&id));
    assert!(fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap()
        .is_some());
    drop(fault);
    // No redelivery: the failed registration never polled the native inbox.
    assert_eq!(retry(&mut fixture, &invite).unwrap().member_count, 2);
    assert_eq!(fixture.store.list_groups().unwrap().len(), 1);
    fixture.restart();
    assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 2);
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .is_empty());
}

#[test]
fn refused_publication_retains_original_crypto_and_target_across_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    fixture.groups.discard_prepared_join(&id);
    let invite = retry_uri(&mut fixture);
    let fault = fail_next_test_publish("first KeyPackage publication refused");
    assert_eq!(
        retry(&mut fixture, &invite).unwrap_err().kind,
        ConversationBridgeErrorKind::Unavailable
    );
    assert!(!fixture.groups.groups.holds(&id));
    let recovery = fixture
        .org
        .offer_recovery(&fixture.org_key, "retryable-offer")
        .unwrap();
    fixture
        .groups
        .prepare_group_restoring(fixture.group_join_request(&invite), recovery)
        .unwrap();
    let cached = prepare_welcome(&mut fixture, &id, &mut admin);
    fixture.groups.discard_prepared_join(&id);
    drop(fault);
    fixture.restart();
    assert_eq!(retry_uri(&mut fixture), invite);
    inbox::deliver(cached);
    assert_eq!(retry(&mut fixture, &invite).unwrap().member_count, 2);
    assert_eq!(fixture.store.list_groups().unwrap().len(), 1);
}
