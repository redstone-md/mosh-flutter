//! Reuse the isolated signed-device fixture: real MLS identities, Moss and redb.
use super::*;
use crate::private_dm_runtime::{contracts::CallAvailability, wire::ControlEnvelope};
use crate::voice_call_runtime::CallState;
use serde_json::json;
#[path = "boundary_tests/boundary_races.rs"]
mod boundary_races;

fn remote_control(
    f: &mut Fixture,
    device: &str,
    peer: &str,
    id: &str,
    sequence: u64,
    action: serde_json::Value,
) -> ControlEnvelope {
    let mut action = action;
    let declared_caller = if id == "selected-call" {
        hex::encode(
            f.runtime
                .session_ref(&f.session)
                .unwrap()
                .crypto
                .signer_public(),
        )
    } else {
        hex::encode(f.peers.get(device).unwrap().signer_public())
    };
    if let Some(end) = action.get_mut("End") {
        if end["caller"].is_null() {
            end["caller"] = declared_caller.into();
        }
    }
    let crypto = f.peers.get_mut(device).unwrap();
    let ciphertext_b64 = crypto
        .encrypt_json(&json!({
            "session_id":f.session, "call_id":id, "signer":hex::encode(crypto.signer_public()),
            "sequence":sequence, "peer":peer, "name":"Other desktop", "action":action
        }))
        .unwrap();
    ControlEnvelope::CallControl {
        session_id: f.session.clone(),
        ciphertext_b64,
    }
}

fn apply(f: &mut Fixture, control: ControlEnvelope) {
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .handle_call_control(control)
        .unwrap();
}

fn admit_second_contact(f: &mut Fixture) {
    admit_outsider(f, false);
}

fn admit_outsider(f: &mut Fixture, own: bool) {
    let sponsor = if own { &f.receiver } else { &f.contact };
    let roster = sponsor
        .roster()
        .extend(f.outsider.device().clone(), &sponsor.key())
        .unwrap();
    if own {
        adopt(&mut f.receiver, roster.clone());
    } else {
        adopt(&mut f.contact, roster.clone());
    }
    adopt(&mut f.outsider, roster.clone());
    let mut crypto = MlsSessionCrypto::new(&f.outsider.device().device_id).unwrap();
    let session = f.runtime.session_mut(&f.session).unwrap();
    let added = session
        .crypto
        .add_members(&[&crypto.key_package_bytes().unwrap()])
        .unwrap();
    for peer in f.peers.values_mut() {
        peer.process_commit(&added.commit_bytes).unwrap();
    }
    crypto
        .join_welcome(&added.welcome_bytes, &added.tree_bytes)
        .unwrap();
    let membership = session.membership.as_mut().unwrap();
    membership
        .topology
        .rosters
        .retain(|old| old.user_id() != roster.user_id());
    membership.topology.rosters.push(roster);
    membership.topology.clients.push(
        IdentityClaim::create(
            &f.outsider,
            &f.session,
            &crypto.signer_public(),
            "Second contact device",
        )
        .unwrap(),
    );
    f.peers
        .insert(f.outsider.device().device_id.clone(), crypto);
}

fn selected_call(f: &mut Fixture) {
    let receiver = hex::encode(
        f.peers
            .get(&f.contact.device().device_id)
            .unwrap()
            .signer_public(),
    );
    let session = f.runtime.session_mut(&f.session).unwrap();
    let mut call = CallState::outgoing(
        "selected-call".into(),
        crate::private_dm_runtime::random_b64(32),
        crate::private_dm_runtime::random_b64(4),
        "Contact".into(),
    );
    call.caller_signer = hex::encode(session.crypto.signer_public());
    call.selected_signer = Some(receiver);
    call.become_active(crate::private_dm_runtime::now_ms());
    session.call = Some(call);
}

fn stale_nonparticipant_terminals_do_not_end_selected_media(f: &mut Fixture) {
    admit_second_contact(f);
    let device = f.outsider.device().device_id.clone();
    let peer = f.outsider.device().moss_peer_id.clone();
    // A real admitted leaf signed these controls before another device was selected.
    let decline = remote_control(
        f,
        &device,
        &peer,
        "selected-call",
        1,
        json!({"Decline":{"reason":"user"}}),
    );
    let end = remote_control(
        f,
        &device,
        &peer,
        "selected-call",
        2,
        json!({"End":{"reason":"hangup"}}),
    );
    selected_call(f);
    apply(f, decline);
    apply(f, end);
    assert!(f.snapshot().active_call.is_some());
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let end = remote_control(
        f,
        &device,
        &peer,
        "selected-call",
        1,
        json!({"End":{"reason":"hangup"}}),
    );
    apply(f, end);
    assert!(f.snapshot().active_call.is_none());
}

fn delayed_occupancy_cannot_replace_a_newer_reservation(f: &mut Fixture) {
    let device = f.source.device().device_id.clone();
    let peer = f.source.device().moss_peer_id.clone();
    let caller = hex::encode(f.peers.get(&device).unwrap().signer_public());
    let old = remote_control(
        f,
        &device,
        &peer,
        "old-call",
        1,
        json!({"Occupied":{"caller":caller,"receiver":null}}),
    );
    let new = remote_control(
        f,
        &device,
        &peer,
        "new-call",
        2,
        json!({"Occupied":{"caller":caller,"receiver":null}}),
    );
    apply(f, new);
    apply(f, old);
    let end = remote_control(
        f,
        &device,
        &peer,
        "old-call",
        3,
        json!({"End":{"reason":"hangup"}}),
    );
    apply(f, end);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
    f.runtime.rehydrate();
    let replay = remote_control(
        f,
        &device,
        &peer,
        "old-call",
        2,
        json!({"Occupied":{"caller":caller,"receiver":null}}),
    );
    apply(f, replay);
    assert!(
        f.snapshot().call_availability.is_none(),
        "restored ordering rejects old occupancy"
    );
}

fn claimed_transport_identity_must_match_the_authenticated_leaf(f: &mut Fixture) {
    selected_call(f);
    let device = f.contact.device().device_id.clone();
    let wrong_peer = f.source.device().moss_peer_id.clone();
    let forged = remote_control(
        f,
        &device,
        &wrong_peer,
        "selected-call",
        1,
        json!({"End":{"reason":"hangup"}}),
    );
    assert!(f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .handle_call_control(forged)
        .is_err());
    assert!(f.snapshot().active_call.is_some());
    let peer = f.contact.device().moss_peer_id.clone();
    let valid = remote_control(
        f,
        &device,
        &peer,
        "selected-call",
        1,
        json!({"End":{"reason":"hangup"}}),
    );
    apply(f, valid);
    assert!(f.snapshot().active_call.is_none());
}

fn known_sibling_occupancy_blocks_an_incoming_call_in_the_same_dm(f: &mut Fixture) {
    let device = f.source.device().device_id.clone();
    let peer = f.source.device().moss_peer_id.clone();
    let caller = hex::encode(f.peers.get(&device).unwrap().signer_public());
    let busy = remote_control(
        f,
        &device,
        &peer,
        "sibling-call",
        1,
        json!({"Occupied":{"caller":caller,"receiver":null}}),
    );
    apply(f, busy);
    let contact = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let offer = remote_control(
        f,
        &contact,
        &peer,
        "another-call",
        1,
        json!({"Offer":{
        "key_b64":crate::private_dm_runtime::random_b64(32), "nonce_prefix_b64":crate::private_dm_runtime::random_b64(4)}}),
    );
    // The offline fixture may refuse transmission of busy; it must refuse admission.
    let _ = f
        .runtime
        .session_mut(&f.session)
        .unwrap()
        .handle_call_control(offer);
    assert!(f.snapshot().pending_call.is_none());
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
}

fn partition_conflict_preserves_the_existing_call_and_reports_admission(f: &mut Fixture) {
    selected_call(f);
    let device = f.source.device().device_id.clone();
    let peer = f.source.device().moss_peer_id.clone();
    let caller = hex::encode(f.peers.get(&device).unwrap().signer_public());
    let competing = remote_control(
        f,
        &device,
        &peer,
        "partition-call",
        1,
        json!({"Occupied":{"caller":caller,"receiver":null}}),
    );
    apply(f, competing);
    let view = f.snapshot();
    assert_eq!(view.active_call.unwrap().call_id, "selected-call");
    assert_eq!(view.call_availability, Some(CallAvailability::Conflict));
    assert!(f.runtime.call_start(&f.session).is_err());
    let end = remote_control(
        f,
        &device,
        &peer,
        "partition-call",
        2,
        json!({"End":{"reason":"hangup"}}),
    );
    apply(f, end);
    let view = f.snapshot();
    assert!(view.active_call.is_some());
    assert_eq!(view.call_availability, Some(CallAvailability::Busy));
}

#[test]
fn signed_call_controls_refuse_stale_devices_and_reordered_occupancy() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::devices::history::packet_tests::calls::call_boundary_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Isolated signed-call fixture worker; the parent invokes it."]
fn call_boundary_process() {
    stale_nonparticipant_terminals_do_not_end_selected_media(&mut Fixture::new());
    delayed_occupancy_cannot_replace_a_newer_reservation(&mut Fixture::new());
    claimed_transport_identity_must_match_the_authenticated_leaf(&mut Fixture::new());
    known_sibling_occupancy_blocks_an_incoming_call_in_the_same_dm(&mut Fixture::new());
    partition_conflict_preserves_the_existing_call_and_reports_admission(&mut Fixture::new());
    boundary_races::canceled_local_presentation_tracks_the_selected_sibling(&mut Fixture::new());
    boundary_races::unconfirmed_sibling_end_cannot_hide_a_selected_call(&mut Fixture::new());
    boundary_races::a_selection_cannot_replace_a_different_live_reservation(&mut Fixture::new());
    boundary_races::a_newer_offer_cannot_discard_an_older_authorized_end(&mut Fixture::new());
    boundary_races::local_end_is_durable_before_returning(&mut Fixture::new());
}
