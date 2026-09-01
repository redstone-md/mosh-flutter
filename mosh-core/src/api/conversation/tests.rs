//! The six shared conversation actions proved against the real runtimes.
//!
//! Every test here drives the live Moss library through the real api
//! singletons — the same locks production drives — serialized on
//! `MOSS_TEST_LOCK` like the other live tests. No doubles: a dispatch is
//! proven by the runtime owner that answers, and each owner is identified
//! by the noun its own error carries ("private DM session", "channel",
//! "group"), so a swapped dispatch arm fails the test instead of silently
//! returning some other kind's error.

use super::{
    cancel_attachment, download_attachment, leave, retry, send, send_attachment,
    BridgeAttachmentPayload, BridgeConversationKind, BridgeConversationRef,
};
use crate::api::conversation_bridge::ConversationBridgeErrorKind;
use crate::moss_ffi::{clear_moss_keystore, MOSS_TEST_LOCK};
use crate::private_dm_runtime::StartSessionRequest;

/// A ref to a conversation that exists in no runtime, per kind.
fn conv_ref(kind: BridgeConversationKind, id: &str) -> BridgeConversationRef {
    BridgeConversationRef {
        kind,
        id: id.to_string(),
    }
}

/// The DM ref used by the missing-conversation grid.
fn dm_ref() -> BridgeConversationRef {
    conv_ref(BridgeConversationKind::Dm, "no-such-session")
}

/// The channel ref used by the missing-conversation grid.
fn channel_ref() -> BridgeConversationRef {
    conv_ref(BridgeConversationKind::Channel, "no-such-channel")
}

/// The group ref used by the missing-conversation grid.
fn group_ref() -> BridgeConversationRef {
    conv_ref(BridgeConversationKind::Group, "no-such-group")
}

/// A plain attachment payload for the dispatch tests; only the encoded
/// bytes vary between calls.
fn payload(data_base64: &str) -> BridgeAttachmentPayload {
    BridgeAttachmentPayload {
        file_name: "f.txt".to_string(),
        mime: "text/plain".to_string(),
        data_base64: data_base64.to_string(),
        thumbnail_base64: None,
        voice: None,
    }
}

/// Asserts the error is the expected category AND names the runtime owner
/// that produced it, so a swapped dispatch arm cannot pass by accident.
fn assert_owner(
    error: super::ConversationBridgeError,
    expected_kind: ConversationBridgeErrorKind,
    owner_noun: &str,
) {
    assert_eq!(
        error.kind, expected_kind,
        "wrong bridge category; message was: {}",
        error.message
    );
    assert!(
        error.message.contains(owner_noun),
        "error must come from the {owner_noun} owner; message was: {}",
        error.message
    );
}

#[test]
fn send_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    assert_owner(
        send(dm_ref(), "hi".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        send(channel_ref(), "hi".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        send(group_ref(), "hi".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

#[test]
fn retry_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    assert_owner(
        retry(dm_ref(), "m-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        retry(channel_ref(), "m-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        retry(group_ref(), "m-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

#[test]
fn send_attachment_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    // The DM runtime resolves the session before its readiness gate, so a
    // missing session reports the lookup miss like every other action.
    assert_owner(
        send_attachment(dm_ref(), payload("aGVsbG8=")).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        send_attachment(channel_ref(), payload("aGVsbG8=")).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        send_attachment(group_ref(), payload("aGVsbG8=")).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

#[test]
fn download_attachment_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    assert_owner(
        download_attachment(dm_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        download_attachment(channel_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        download_attachment(group_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

#[test]
fn cancel_attachment_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    assert_owner(
        cancel_attachment(dm_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        cancel_attachment(channel_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        cancel_attachment(group_ref(), "a-1".to_string()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

#[test]
fn leave_reaches_every_kind_owner() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    assert_owner(
        leave(dm_ref()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "private DM session",
    );
    assert_owner(
        leave(channel_ref()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "channel not joined",
    );
    assert_owner(
        leave(group_ref()).unwrap_err(),
        ConversationBridgeErrorKind::MissingConversation,
        "group not joined",
    );
}

/// The decode happens before any runtime is touched, so a bad payload is an
/// `InvalidInput` for every kind without needing the Moss library.
#[test]
fn send_attachment_rejects_an_undecodable_payload() {
    let error = send_attachment(
        conv_ref(BridgeConversationKind::Channel, "any-channel"),
        payload("!!not base64!!"),
    )
    .unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::InvalidInput);
    assert!(
        error.message.contains("base64"),
        "message should say the payload was not base64; was: {}",
        error.message
    );
}

/// All six actions against one real DM session living inside the real
/// singleton runtime: the creator side of a fresh invite, before any peer
/// joins. This is the proof the seam works against a real conversation, not
/// only against lookups that miss. Leaving at the end both proves the last
/// action and cleans the session up.
///
/// The shared resources this test constructs stay for the process lifetime
/// (OnceLock singletons), but the keystore they arm is disarmed here, so a
/// later node-init test still gets Moss's mint-a-fresh-identity baseline —
/// the same courtesy `api::private_dm`'s persistence test extends.
#[test]
fn the_shared_actions_drive_a_real_dm_session() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let invite = crate::api::private_dm::create_invite(StartSessionRequest {
        display_name: "Bridge Dispatch".to_string(),
        // A port no other test uses; the shared node is born on the first
        // caller's port and this test is serialized behind MOSS_TEST_LOCK.
        listen_port: 43390,
        static_peer: None,
    })
    .expect("invite should be created");
    let dm = conv_ref(BridgeConversationKind::Dm, &invite.session_id);

    // Sending into the real session succeeds — the creator owns the MLS
    // group from the moment the invite exists — and the success payload is
    // dropped: the answer is `()`, not a send-result DTO.
    send(dm.clone(), "hello nobody yet".to_string())
        .expect("send should succeed on a real session");

    // Retry on a real session with no such attempt.
    let error = retry(dm.clone(), "m-none".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingMessage);

    // Attachment sends are gated on the peer being joined; the session is
    // real and waiting, so the runtime's own gate refuses with NotReady.
    let error = send_attachment(dm.clone(), payload("aGVsbG8=")).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::NotReady);
    let error = download_attachment(dm.clone(), "a-none".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingAttachment);
    let error = cancel_attachment(dm.clone(), "a-none".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingAttachment);

    // Leaving a real session succeeds and drops the success payload.
    leave(dm.clone()).expect("leave should succeed on a real session");
    // The session is genuinely gone: the next send misses the lookup.
    let error = send(dm, "anyone there?".to_string()).unwrap_err();
    assert_eq!(error.kind, ConversationBridgeErrorKind::MissingConversation);

    disarm_shared_keystore();
}

/// Disarms the keystore the shared resources armed, restoring the baseline
/// for any later node-init test in this binary — the same courtesy
/// `api::private_dm`'s persistence test extends at its teardown.
fn disarm_shared_keystore() {
    let moss = crate::moss_ffi::MossFfiRuntime::load_default().expect("library should load");
    let _ = moss.uninstall_keystore();
    clear_moss_keystore();
}
