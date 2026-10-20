use super::*;

pub(super) fn outgoing_and_incoming_history_retain_the_caller(f: &mut Fixture) {
    selected_call(f);
    let local = f.snapshot().display_name;
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .finish_call("completed", 86_000);
    let history = f.snapshot();
    let message = history.messages.last().unwrap();
    assert_eq!(
        message.from_device, local,
        "outgoing history belongs to the caller"
    );
    assert_eq!(message.metadata.as_ref().unwrap().is_own, Some(true));
    assert_eq!(message.call_event.as_ref().unwrap().duration_ms, 86_000);

    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let offer = remote_control(
        f,
        &device,
        &peer,
        "incoming-history",
        2,
        json!({"Offer":{"key_b64": crate::private_dm_runtime::random_b64(32),
            "nonce_prefix_b64": crate::private_dm_runtime::random_b64(4)}}),
    );
    apply(f, offer);
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .finish_call("missed", 0);
    let history = f.snapshot();
    let message = history.messages.last().unwrap();
    assert_eq!(message.from_device, "Other desktop");
    assert_eq!(message.metadata.as_ref().unwrap().is_own, Some(false));
    assert_eq!(message.call_event.as_ref().unwrap().kind, "missed");
}
