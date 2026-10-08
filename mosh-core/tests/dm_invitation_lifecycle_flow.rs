//! Invitations use independent installations, real Moss discovery and OpenMLS.
mod invitation_support;
#[allow(
    dead_code,
    reason = "Reuse the independent-process harness without its device-link scenarios."
)]
mod link_support;

use invitation_support::{
    accept, create, evidence, installation, pending, poll, send, sessions, wait_connected,
    wait_rejected,
};
use link_support::isolated_network_scenario;
use serde_json::json;

#[test]
fn compact_hidden_invitation_connects_and_exchanges_real_text() {
    let _network = isolated_network_scenario();
    let mut creator = installation();
    let mut contact = installation();
    let invite = create(&mut creator);
    let uri = invite["invite_uri"].as_str().unwrap();
    assert!(uri.starts_with("mosh://invite/"));
    assert!(uri.len() <= 320, "autonomous invitation remains compact");
    assert!(sessions(&mut creator).is_empty());
    accept(&mut contact, &invite, "Contact");
    let id = invite["session_id"].as_str().unwrap();
    let (alice, bob) = wait_connected(&mut creator, &mut contact, id);
    assert_eq!(alice["fingerprint"], invite["fingerprint"]);
    assert_eq!(bob["fingerprint"], invite["fingerprint"]);
    assert_eq!(alice["invite_available"], false);
    assert_eq!(sessions(&mut creator).len(), 1);
    assert!(pending(&mut creator).is_empty());
    send(&mut creator, id, "From creator");
    contact.wait_dm_text(id, "From creator");
    send(&mut contact, id, "From contact");
    creator.wait_dm_text(id, "From contact");
}

#[test]
fn saved_pending_invitations_restore_and_open_only_once() {
    let _network = isolated_network_scenario();
    let mut creator = installation();
    let first = create(&mut creator);
    let second = create(&mut creator);
    assert_ne!(first["session_id"], second["session_id"]);
    assert!(sessions(&mut creator).is_empty());
    creator.restart();
    let saved = pending(&mut creator);
    assert_eq!(saved.len(), 2);
    for invite in [&first, &second] {
        assert!(saved
            .iter()
            .any(|item| item["invite_uri"] == invite["invite_uri"]));
    }
    assert!(sessions(&mut creator).is_empty());
    let id = first["session_id"].as_str().unwrap();
    for _ in 0..2 {
        let opened = creator.ask(json!({"action":"open", "argument":id}));
        assert_eq!(opened["session_id"], id);
        assert_eq!(opened["invite_available"], true);
    }
    creator.restart();
    let visible = sessions(&mut creator);
    assert_eq!(visible.len(), 1);
    assert_eq!(visible[0]["session_id"], id);
    assert!(visible[0]["invite_uri"] == first["invite_uri"]);
    let hidden = pending(&mut creator);
    assert_eq!(hidden.len(), 1);
    assert!(hidden[0]["invite_uri"] == second["invite_uri"]);
}

#[test]
fn replacement_rejects_the_old_invitation_and_admits_the_new_one_in_place() {
    let _network = isolated_network_scenario();
    let mut creator = installation();
    let mut stale_contact = installation();
    let mut contact = installation();
    let old = create(&mut creator);
    let independent = create(&mut creator);
    let id = old["session_id"].as_str().unwrap();
    creator.ask(json!({"action":"open", "argument":id}));
    let replacement = creator.ask(json!({"action":"replace", "argument":id}));
    assert_eq!(replacement["session_id"], id);
    assert_eq!(replacement["mesh_id"], old["mesh_id"]);
    assert!(replacement["invite_uri"] != old["invite_uri"]);
    creator.restart();
    accept(&mut stale_contact, &old, "Stale contact");
    wait_rejected(
        &mut creator,
        &mut stale_contact,
        id,
        "invitation has been replaced",
        0,
        1,
    );
    assert_eq!(poll(&mut creator, id)["invite_available"], true);
    assert_eq!(sessions(&mut creator).len(), 1);
    let hidden = pending(&mut creator);
    assert_eq!(hidden.len(), 1);
    assert!(hidden[0]["invite_uri"] == independent["invite_uri"]);
    accept(&mut contact, &replacement, "Contact");
    wait_connected(&mut creator, &mut contact, id);
    send(&mut contact, id, "New invitation works");
    creator.wait_dm_text(id, "New invitation works");
    assert_eq!(sessions(&mut creator).len(), 1);
    assert_eq!(evidence(&mut creator, id, "")["members"], 2);
    assert_eq!(poll(&mut stale_contact, id)["state"], "pending");
}

#[test]
fn creator_restart_before_any_text_keeps_admission_consumed_and_refuses_another_peer() {
    let _network = isolated_network_scenario();
    let mut creator = installation();
    let mut contact = installation();
    let invite = create(&mut creator);
    let id = invite["session_id"].as_str().unwrap();
    accept(&mut contact, &invite, "Contact");
    let (alice, bob) = wait_connected(&mut creator, &mut contact, id);
    assert!(alice["messages"].as_array().unwrap().is_empty());
    assert!(bob["messages"].as_array().unwrap().is_empty());
    creator.crash();
    creator.restart();
    assert!(pending(&mut creator).is_empty());
    let restored = poll(&mut creator, id);
    assert_eq!(restored["invite_available"], false);
    assert!(restored["messages"].as_array().unwrap().is_empty());
    let refused = creator.ask(json!({"action":"replace", "argument":id}));
    assert!(refused["error"].is_string());
    let baseline = evidence(&mut creator, id, "invitation already used")["rejections"]
        .as_u64()
        .unwrap();
    let mut outsider = installation();
    accept(&mut outsider, &invite, "Outsider");
    wait_rejected(
        &mut creator,
        &mut outsider,
        id,
        "invitation already used",
        baseline,
        2,
    );
    assert_eq!(poll(&mut creator, id)["peer_display_name"], "Contact");
    wait_connected(&mut creator, &mut contact, id);
    send(&mut contact, id, "First text after restart");
    creator.wait_dm_text(id, "First text after restart");
    assert_eq!(poll(&mut creator, id)["invite_available"], false);
    assert!(pending(&mut creator).is_empty());
    assert_eq!(sessions(&mut creator).len(), 1);
}

#[test]
#[ignore = "worker launched by independent-installation invitation tests"]
fn invitation_installation_process() {
    invitation_support::worker::run();
}
