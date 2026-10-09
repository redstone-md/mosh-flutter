use super::*;
use crate::voice_call_runtime::CallPhase;

pub(super) fn media_retries_cannot_suppress_the_callers_selection(f: &mut Fixture) {
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let caller = hex::encode(f.peers.get(&device).unwrap().signer_public());
    let session = f.runtime.session_mut(&f.session).unwrap();
    let receiver = hex::encode(session.crypto.signer_public());
    let mut call = CallState::ringing(
        "media-race".into(),
        "k".into(),
        "n".into(),
        "Contact".into(),
    );
    call.caller_signer = caller.clone();
    call.remote_peer = peer.clone();
    call.phase = CallPhase::Accepting;
    call.mark_offer_sent(crate::private_dm_runtime::now_ms());
    session.call = Some(call);
    let media = remote_control(
        f,
        &device,
        &peer,
        "media-race",
        100,
        json!({"Media":{"Description":{
        "binding":{"session_id":f.session,"call_id":"media-race","caller":caller,"callee":receiver,"media_session":vec![7;16]},
        "offer":true,"parameters":[1]}}}),
    );
    apply(f, media);
    let selected = remote_control(
        f,
        &device,
        &peer,
        "media-race",
        2,
        json!({"Selected":{"receiver":receiver}}),
    );
    apply(f, selected);
    assert!(f.snapshot().active_call.is_some());
}

pub(super) fn only_the_selected_leaf_can_submit_bound_native_media(f: &mut Fixture) {
    admit_second_contact(f);
    selected_call(f);
    let peer = f.contact.device().moss_peer_id.clone();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .call
        .as_mut()
        .unwrap()
        .remote_peer = peer.clone();
    let device = f.outsider.device().device_id.clone();
    let outside_peer = f.outsider.device().moss_peer_id.clone();
    let signal = json!({"Media":{"Candidates":{"nonce":vec![7;16],"candidates":["candidate"]}}});
    let unselected = remote_control(
        f,
        &device,
        &outside_peer,
        "selected-call",
        900,
        signal.clone(),
    );
    apply(f, unselected);
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .call
        .as_ref()
        .unwrap()
        .native_controls
        .is_empty());
    let device = f.contact.device().device_id.clone();
    let valid = remote_control(f, &device, &peer, "selected-call", 1, signal);
    apply(f, valid);
    assert_eq!(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .call
            .as_ref()
            .unwrap()
            .native_controls
            .len(),
        1
    );
}

pub(super) fn current_removal_evidence_ends_only_the_selected_pair(f: &mut Fixture) {
    admit_second_contact(f);
    selected_call(f);
    let removed_other = f
        .contact
        .roster()
        .revoke(&f.outsider.device().device_id, &f.contact.key())
        .unwrap();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .membership
        .as_mut()
        .unwrap()
        .pin_roster(&removed_other)
        .unwrap();
    f.runtime.reconcile_call_authority();
    assert!(f.snapshot().active_call.is_some());
}

pub(super) fn selected_device_removal_releases_native_call(f: &mut Fixture) {
    admit_second_contact(f);
    selected_call(f);
    let removed_selected = f
        .contact
        .roster()
        .revoke(&f.contact.device().device_id, &f.outsider.key())
        .unwrap();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .membership
        .as_mut()
        .unwrap()
        .pin_roster(&removed_selected)
        .unwrap();
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .native_context()
        .is_none());
    f.runtime.reconcile_call_authority();
    f.runtime.sync_call_media();
    assert!(f.snapshot().active_call.is_none());
    assert!(f.snapshot().call_availability.is_none());
}

pub(super) fn local_removal_revokes_retained_native_call(f: &mut Fixture) {
    selected_call(f);
    let removed = f
        .receiver
        .roster()
        .revoke(&f.receiver.device().device_id, &f.source.key())
        .unwrap();
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .membership
        .as_mut()
        .unwrap()
        .pin_roster(&removed)
        .unwrap();
    assert!(f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .native_context()
        .is_none());
    f.runtime.reconcile_call_authority();
    assert!(f.snapshot().active_call.is_none());
}

pub(super) fn unsupported_media_installation_does_not_ring_or_select(f: &mut Fixture) {
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let offer = remote_control(
        f,
        &device,
        &peer,
        "incompatible",
        1,
        json!({"Offer":{
        "native": !cfg!(any(target_os = "windows", target_os = "macos", target_os = "linux")), "key_b64":crate::private_dm_runtime::random_b64(32),
        "nonce_prefix_b64":crate::private_dm_runtime::random_b64(4)}}),
    );
    apply(f, offer);
    assert!(f.snapshot().pending_call.is_none());
}

pub(super) fn reordered_camera_state_cannot_reenable_a_stopped_remote_track(f: &mut Fixture) {
    selected_call(f);
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    for (sequence, enabled) in [(100, false), (99, true)] {
        let control = remote_control(
            f,
            &device,
            &peer,
            "selected-call",
            sequence,
            json!({"Media":{"Camera":{"nonce":vec![7;16],"enabled":enabled}}}),
        );
        apply(f, control);
    }
    let queued = &f
        .runtime
        .session_ref(&f.session)
        .unwrap()
        .call
        .as_ref()
        .unwrap()
        .native_controls;
    assert_eq!(queued.len(), 1);
    assert!(matches!(
        queued.front(),
        Some(crate::native_call::types::Signal::Camera { enabled: false, .. })
    ));
}
