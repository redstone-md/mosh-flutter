use super::*;
use crate::test_temp_directory::TempDirectory;

fn incoming() -> BackgroundCallState {
    BackgroundCallState {
        session_id: "session".into(),
        call_id: "call".into(),
        phase: BackgroundCallPhase::Incoming,
        expires_at_ms: 30_000,
        sender: "Verified caller".into(),
        binding: "verified binding".into(),
    }
}

#[test]
fn call_capabilities_are_single_use_and_bound_to_exact_live_state() {
    let directory = TempDirectory::new("background-call-actions");
    let store =
        Persistence::open_with_dek(&directory.path().join("history.redb"), [91; 32]).unwrap();
    let call = incoming();
    store
        .sync_background_calls("owner-one", std::slice::from_ref(&call))
        .unwrap();
    let pending = store.pending_background_notifications(16).unwrap();
    let answer = pending[0]
        .call
        .as_ref()
        .unwrap()
        .answer_capability
        .as_ref()
        .unwrap();
    assert!(store
        .take_background_call_action(answer, "owner-two", &call, 1)
        .unwrap()
        .is_none());
    let mut other = call.clone();
    other.call_id = "newer call".into();
    assert!(store
        .take_background_call_action(answer, "owner-one", &other, 1)
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .take_background_call_action(answer, "owner-one", &call, 1)
            .unwrap(),
        Some(BackgroundCallAction::Answer)
    );
    assert!(store
        .take_background_call_action(answer, "owner-one", &call, 1)
        .unwrap()
        .is_none());
}

#[test]
fn call_expiry_reclaim_and_stale_ack_cannot_ring_or_affect_a_newer_call() {
    let directory = TempDirectory::new("background-call-restart");
    let path = directory.path().join("history.redb");
    let store = Persistence::open_with_dek(&path, [92; 32]).unwrap();
    let call = incoming();
    store
        .sync_background_calls("owner-one", std::slice::from_ref(&call))
        .unwrap();
    let first = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    let cap = first
        .call
        .as_ref()
        .unwrap()
        .decline_capability
        .as_ref()
        .unwrap();
    assert!(store
        .take_background_call_action(cap, "owner-one", &call, 30_000)
        .unwrap()
        .is_none());
    drop(store);
    let store = Persistence::open_with_dek(&path, [92; 32]).unwrap();
    store.sync_background_calls("owner-two", &[]).unwrap();
    store
        .ack_background_notification(&first.id, first.revision)
        .unwrap();
    let ended = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    assert_eq!(ended.id, first.id);
    assert!(ended.revision > first.revision);
    assert_eq!(
        ended.call.as_ref().unwrap().phase,
        BackgroundCallPhase::Ended
    );
    assert!(store
        .take_background_call_action(cap, "owner-two", &call, 1)
        .unwrap()
        .is_none());
}

#[test]
fn declined_and_active_actions_do_not_cross_phases_and_terminal_ack_retires_them() {
    let directory = TempDirectory::new("background-call-phase");
    let path = directory.path().join("history.redb");
    let store = Persistence::open_with_dek(&path, [93; 32]).unwrap();
    let mut call = incoming();
    store
        .sync_background_calls("owner", std::slice::from_ref(&call))
        .unwrap();
    let incoming = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    let old = incoming
        .call
        .as_ref()
        .unwrap()
        .decline_capability
        .as_ref()
        .unwrap();
    call.phase = BackgroundCallPhase::Active;
    call.expires_at_ms = 0;
    store
        .sync_background_calls("owner", std::slice::from_ref(&call))
        .unwrap();
    assert!(store
        .take_background_call_action(old, "owner", &call, 1)
        .unwrap()
        .is_none());
    let active = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    let hangup = active
        .call
        .as_ref()
        .unwrap()
        .hangup_capability
        .as_ref()
        .unwrap();
    assert_eq!(
        store
            .take_background_call_action(hangup, "owner", &call, u64::MAX)
            .unwrap(),
        Some(BackgroundCallAction::Hangup)
    );
    assert!(store
        .take_background_call_action("not-a-capability", "owner", &call, 1)
        .unwrap()
        .is_none());
    assert!(store
        .take_background_call_action(&"A".repeat(64), "owner", &call, 1)
        .unwrap()
        .is_none());
    store.sync_background_calls("owner", &[]).unwrap();
    let end = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    store
        .ack_background_notification(&end.id, end.revision)
        .unwrap();
    assert!(store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
    assert!(store
        .background_call_for_capability(hangup, "owner")
        .unwrap()
        .is_none());
    let bytes = std::fs::read(path).unwrap();
    assert!(!bytes
        .windows(hangup.len())
        .any(|window| window == hangup.as_bytes()));
}

#[test]
fn refused_capability_commit_preserves_the_action_for_a_durable_retry() {
    let directory = TempDirectory::new("background-call-refusal");
    let store = std::sync::Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [94; 32]).unwrap(),
    );
    let call = incoming();
    store
        .sync_background_calls("owner", std::slice::from_ref(&call))
        .unwrap();
    let first = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    let answer = first
        .call
        .as_ref()
        .unwrap()
        .answer_capability
        .as_ref()
        .unwrap();
    let fault = store.refuse_background_delivery_writes();
    assert!(store
        .take_background_call_action(answer, "owner", &call, 1)
        .is_err());
    drop(fault);
    assert_eq!(
        store
            .take_background_call_action(answer, "owner", &call, 1)
            .unwrap(),
        Some(BackgroundCallAction::Answer)
    );
    // Consuming and renewing are one commit: an interrupted permission dialog
    // must not leave a spent OS button without a retryable replacement.
    let newer = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    assert!(newer.revision > first.revision);
    assert_ne!(
        newer.call.as_ref().unwrap().answer_capability.as_ref(),
        Some(answer)
    );
    assert!(store
        .background_call_for_capability(answer, "owner")
        .unwrap()
        .is_none());
}
