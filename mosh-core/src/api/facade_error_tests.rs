//! The kind-specific facade actions hand their runtime error to the bridge
//! by kind, not as a sentence (ticket 17). One live test per runtime, each
//! through the real singleton and serialized on `MOSS_TEST_LOCK` like the
//! other live tests. The taxonomy itself is proven variant by variant in
//! `conversation_bridge`; these tests prove the facades reach it.

use crate::api::conversation_bridge::ConversationBridgeErrorKind;
use crate::api::{channel, org, private_dm, private_group};
use crate::channel_runtime::JoinChannelRequest;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::org_runtime::JoinOrgRequest;
use crate::private_dm_runtime::AcceptInviteRequest;
use crate::private_group_runtime::JoinGroupRequest;

/// The port the shared node is born on if one of these tests is its first
/// caller; the node is a process singleton, so later callers ignore it.
const LISTEN_PORT: u16 = 43392;

/// A paste that is not an invite is the caller's mistake; a call into a
/// session we do not hold misses the lookup.
#[test]
fn the_dm_actions_report_failures_by_kind() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let error = private_dm::accept_invite(AcceptInviteRequest {
        invite_uri: "not an invite".to_string(),
        display_name: "Facade".to_string(),
        listen_port: LISTEN_PORT,
        static_peer: None,
    })
    .unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::InvalidInput);
    assert!(
        error.message.contains("invalid invite"),
        "{}",
        error.message
    );

    let error = private_dm::call_start("no-such-session".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingConversation);
}

/// An empty channel name is the caller's mistake.
#[test]
fn channel_join_reports_an_invalid_name_by_kind() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let error = channel::join(JoinChannelRequest {
        name: String::new(),
        display_name: "Facade".to_string(),
        listen_port: LISTEN_PORT,
        static_peer: None,
    })
    .unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::InvalidInput);
    assert!(
        error.message.contains("invalid channel name"),
        "{}",
        error.message
    );
}

/// A paste that is not a group invite is the caller's mistake.
#[test]
fn group_join_reports_an_invalid_invite_by_kind() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let error = private_group::join_group(JoinGroupRequest {
        invite_uri: "not a group invite".to_string(),
        display_name: "Facade".to_string(),
        org_pubkey: None,
        listen_port: LISTEN_PORT,
        static_peer: None,
    })
    .unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::InvalidInput);
    assert!(
        error.message.contains("invalid group invite"),
        "{}",
        error.message
    );
}

/// `OrgError` reaches the bridge through the one `From<OrgError>` impl: a
/// bundle that is not an org URI is the caller's mistake, and leaving an org
/// we never joined misses the lookup.
#[test]
fn the_org_actions_report_failures_by_kind() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let error = org::join_org(JoinOrgRequest {
        bundle_uri: "not an org bundle".to_string(),
        display_name: "Facade".to_string(),
        listen_port: LISTEN_PORT,
        static_peer: None,
    })
    .unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::InvalidInput);
    assert!(
        error.message.contains("invalid org bundle"),
        "{}",
        error.message
    );

    let error = org::leave_org("no-such-org".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingConversation);
    assert!(
        error.message.contains("not joined to org"),
        "{}",
        error.message
    );
}
