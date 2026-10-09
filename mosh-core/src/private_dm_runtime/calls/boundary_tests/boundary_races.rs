use super::*;

fn signer(f: &Fixture, identity: &DeviceIdentity) -> String {
    hex::encode(
        f.peers
            .get(&identity.device().device_id)
            .unwrap()
            .signer_public(),
    )
}

fn occupied(f: &mut Fixture, id: &str, sequence: u64) -> ControlEnvelope {
    let device = f.source.device().device_id.clone();
    let peer = f.source.device().moss_peer_id.clone();
    let receiver = signer(f, &f.source);
    let caller = signer(f, &f.contact);
    remote_control(
        f,
        &device,
        &peer,
        id,
        sequence,
        json!({"Occupied":{"caller":caller,"receiver":receiver}}),
    )
}

pub(super) fn canceled_local_presentation_tracks_the_selected_sibling(f: &mut Fixture) {
    let contact = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let offer = remote_control(
        f,
        &contact,
        &peer,
        "race-call",
        1,
        json!({"Offer":{
        "key_b64":crate::private_dm_runtime::random_b64(32), "nonce_prefix_b64":crate::private_dm_runtime::random_b64(4)}}),
    );
    apply(f, offer);
    // Local presentation ended before its decline could reach the caller.
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .finish_call("missed", 0);
    let busy = occupied(f, "race-call", 1);
    apply(f, busy);
    let view = f.snapshot();
    assert!(view.pending_call.is_none());
    assert!(view.active_call.is_none());
    assert_eq!(view.call_availability, Some(CallAvailability::Busy));
}

pub(super) fn unconfirmed_sibling_end_cannot_hide_a_selected_call(f: &mut Fixture) {
    admit_outsider(f, true);
    let device = f.outsider.device().device_id.clone();
    let peer = f.outsider.device().moss_peer_id.clone();
    let caller = signer(f, &f.contact);
    let stale = remote_control(
        f,
        &device,
        &peer,
        "race-call",
        1,
        json!({"End":{"caller":caller,"reason":"cancel"}}),
    );
    apply(f, stale);
    let busy = occupied(f, "race-call", 1);
    apply(f, busy);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
}

pub(super) fn a_selection_cannot_replace_a_different_live_reservation(f: &mut Fixture) {
    admit_second_contact(f);
    let busy = occupied(f, "original-call", 1);
    apply(f, busy);
    let device = f.outsider.device().device_id.clone();
    let peer = f.outsider.device().moss_peer_id.clone();
    let receiver = signer(f, &f.source);
    let unrelated = remote_control(
        f,
        &device,
        &peer,
        "unrelated-call",
        1,
        json!({"Selected":{"receiver":receiver}}),
    );
    apply(f, unrelated);
    let end = remote_control(
        f,
        &device,
        &peer,
        "unrelated-call",
        2,
        json!({"End":{"reason":"cancel"}}),
    );
    apply(f, end);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
}

pub(super) fn a_newer_offer_cannot_discard_an_older_authorized_end(f: &mut Fixture) {
    selected_call(f);
    let contact = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let end = remote_control(
        f,
        &contact,
        &peer,
        "selected-call",
        1,
        json!({"End":{"reason":"hangup"}}),
    );
    let newer = remote_control(
        f,
        &contact,
        &peer,
        "another-call",
        2,
        json!({"Offer":{
        "key_b64":crate::private_dm_runtime::random_b64(32), "nonce_prefix_b64":crate::private_dm_runtime::random_b64(4)}}),
    );
    apply(f, newer);
    apply(f, end);
    assert!(f.snapshot().active_call.is_none());
}

pub(super) fn local_end_is_durable_before_returning(f: &mut Fixture) {
    selected_call(f);
    let _ = f.runtime.call_end(&f.session, "selected-call", "hangup");
    f.runtime.rehydrate();
    let contact = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let late = remote_control(
        f,
        &contact,
        &peer,
        "selected-call",
        1,
        json!({"Offer":{
        "key_b64":crate::private_dm_runtime::random_b64(32), "nonce_prefix_b64":crate::private_dm_runtime::random_b64(4)}}),
    );
    apply(f, late);
    assert!(f.snapshot().pending_call.is_none());
}
