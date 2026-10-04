use super::*;

const GROUP_URI: &str =
    "mosh://group?mesh=peer-group&group=peer-group#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

#[test]
fn malformed_group_invite_does_not_consume_the_org_offer() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.deliver_group_offer("malformed invite");
    let request = fixture.group_join_request("malformed invite");
    let result = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::InvalidInput
    );
    assert_eq!(
        fixture
            .org
            .poll(&fixture.org_key)
            .unwrap()
            .group_offers
            .len(),
        1
    );
}

#[test]
fn refused_group_key_package_keeps_offer_for_successful_retry() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.deliver_group_offer(GROUP_URI);
    let fault = fail_next_test_publish("first group key package failed");
    let request = fixture.group_join_request(GROUP_URI);
    let result = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::Unavailable
    );
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
    drop(fault);
    let request = fixture.group_join_request(GROUP_URI);
    workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .is_empty());
    assert_eq!(fixture.groups.list().unwrap().groups.len(), 1);
}

#[test]
fn refused_group_resolution_preserves_offer_and_existing_group() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let request = fixture.group_request();
    let existing = fixture.groups.create_group(request).unwrap().group_id;
    fixture.deliver_group_offer(GROUP_URI);
    let fault = fixture.store.refuse_org_record_writes();
    let request = fixture.group_join_request(GROUP_URI);
    let result = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    );
    assert_eq!(
        result.unwrap_err().kind,
        ConversationBridgeErrorKind::Persistence
    );
    assert_eq!(
        fixture
            .org
            .poll(&fixture.org_key)
            .unwrap()
            .group_offers
            .len(),
        1
    );
    let groups = fixture.groups.list().unwrap().groups;
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].group_id, existing);
    drop(fault);
    let request = fixture.group_join_request(GROUP_URI);
    workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
}

#[test]
fn accepted_pending_group_offer_is_recoverable_after_restart_without_redelivery() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.deliver_group_offer(GROUP_URI);
    let request = fixture.group_join_request(GROUP_URI);
    let snapshot = workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
    assert_eq!(snapshot.state, "waiting");
    assert!(fixture.store.list_groups().unwrap().is_empty());
    assert!(fixture
        .org
        .poll(&fixture.org_key)
        .unwrap()
        .group_offers
        .is_empty());
    fixture.restart();
    let snapshot = fixture.org.poll(&fixture.org_key).unwrap();
    assert_eq!(snapshot.group_offers.len(), 1);
    assert_eq!(snapshot.group_offers[0].group_invite_uri, GROUP_URI);
    fixture.deliver_group_offer(GROUP_URI);
    assert_eq!(
        fixture
            .org
            .poll(&fixture.org_key)
            .unwrap()
            .group_offers
            .len(),
        1
    );
    let request = fixture.group_join_request(GROUP_URI);
    workflows::accept_and_join_group(
        &mut fixture.org,
        &mut fixture.groups,
        &fixture.org_key,
        "retryable-offer",
        request,
    )
    .unwrap();
}
