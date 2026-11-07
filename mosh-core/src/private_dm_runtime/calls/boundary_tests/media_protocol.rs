//! Devices whose engines speak different media protocols cannot connect
//! media: the call ends with `update_required` instead of ringing forever
//! or connecting nothing.
use super::*;

const OTHER_ENGINE: u32 = 0xFFFF;

fn handle(f: &mut Fixture, control: ControlEnvelope) {
    // The offline fixture may refuse to transmit the reply; the outcome is local.
    let _ = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .handle_call_control(control);
}

fn call_events(f: &mut Fixture) -> Vec<(String, Option<bool>)> {
    f.snapshot()
        .messages
        .into_iter()
        .filter_map(|message| {
            let own = message.metadata.and_then(|metadata| metadata.is_own);
            message.call_event.map(|event| (event.kind, own))
        })
        .collect()
}

fn outgoing_call(f: &mut Fixture) {
    let session = f.runtime.session_mut(&f.session).unwrap();
    let mut call = CallState::outgoing("outgoing-call".into(), "Contact".into());
    call.caller_signer = hex::encode(session.crypto.signer_public());
    call.mark_offer_sent(crate::private_dm_runtime::now_ms());
    session.call = Some(call);
}

// An older client speaks the legacy protocol. A build whose engine failed to
// load must not take it for its own and ring a call neither side can carry.
pub(super) fn an_offer_from_another_engine_is_refused_once_with_update_required(f: &mut Fixture) {
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    for sequence in 1..=2 {
        let offer = remote_control_on(
            f,
            &device,
            &peer,
            "other-engine",
            sequence,
            // An older client's offer still carries its own media keys.
            json!({"Offer":{"key_b64":"a2V5", "nonce_prefix_b64":"bm9uYw==", "native":true}}),
            crate::native_call::LEGACY_MEDIA_PROTOCOL,
        );
        handle(f, offer);
    }
    assert!(f.snapshot().pending_call.is_none(), "never rings");
    assert_eq!(
        call_events(f),
        [("update_required".to_owned(), Some(false))],
        "a resent offer records no second event"
    );
}

pub(super) fn an_answer_from_another_engine_ends_the_outgoing_call(f: &mut Fixture) {
    outgoing_call(f);
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let answer = remote_control_on(
        f,
        &device,
        &peer,
        "outgoing-call",
        1,
        json!("Answer"),
        OTHER_ENGINE,
    );
    handle(f, answer);
    let view = f.snapshot();
    assert!(view.active_call.is_none() && view.outgoing_call.is_none());
    assert_eq!(call_events(f), [("update_required".to_owned(), Some(true))]);
}

pub(super) fn an_engine_refusal_rings_on_then_asks_to_update(f: &mut Fixture) {
    outgoing_call(f);
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let decline = remote_control(
        f,
        &device,
        &peer,
        "outgoing-call",
        1,
        json!({"Decline":{"reason":"update_required"}}),
    );
    handle(f, decline);
    assert!(
        f.snapshot().outgoing_call.is_some(),
        "the contact's other devices still ring"
    );
    let session = f.runtime.session_mut(&f.session).unwrap();
    let rang = session.call.as_ref().unwrap().offer_first_ms;
    session.pump_call_signaling(rang + crate::private_dm_runtime::CALL_RING_TIMEOUT_MS);
    assert!(f.snapshot().outgoing_call.is_none());
    assert_eq!(call_events(f), [("update_required".to_owned(), Some(true))]);
}
