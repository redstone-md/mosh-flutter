use super::link_support::{isolated_network_scenario, Peer};
use serde_json::json;

#[test]
fn only_one_linked_receiver_is_selected_and_its_occupancy_is_released() {
    let _network = isolated_network_scenario();
    let (mut caller, mut first, mut second) = (Peer::new_api(), Peer::new_api(), Peer::new_api());
    let qr = first.ask(json!({"action":"qr"}));
    second.ask(json!({"action":"import", "argument":qr["qr_uri"], "name":"Second receiver"}));
    first.wait_phase("AwaitingApproval");
    let pending = second.wait_phase("AwaitingConfirmation");
    first.ask(json!({"action":"approve", "argument":pending["confirmation_code"]}));
    first.wait_phase("Linked");
    second.wait_phase("Linked");

    let invite = caller.ask(json!({"action":"dm_invite"}));
    first.ask(json!({"action":"dm_accept", "argument":invite["invite_uri"]}));
    let session = invite["session_id"].as_str().unwrap();
    caller.ask(json!({"action":"dm_send", "argument":session, "body":"Call admission ready"}));
    first.wait_dm_text(session, "Call admission ready");
    wait_call_view(&mut second, session, |view| view["state"] == "connected");

    let call = caller.ask(json!({"action":"call_start", "argument":session}));
    assert!(call["error"].is_null(), "start failed: {call}");
    let call_id = &call["call_id"];
    wait_call_view(&mut first, session, |view| {
        view["pending_call"]["call_id"] == *call_id
    });
    wait_call_view(&mut second, session, |view| {
        view["pending_call"]["call_id"] == *call_id
    });
    first.ask(json!({"action":"call_accept", "argument":session, "call_id":call_id}));
    wait_call_view(&mut caller, session, |view| {
        view["active_call"]["call_id"] == *call_id
    });
    wait_call_view(&mut first, session, |view| {
        view["active_call"]["call_id"] == *call_id
    });
    wait_call_view(&mut second, session, |view| view["pending_call"].is_null());
    assert!(second.ask(json!({"action":"dm_poll", "argument":session}))["active_call"].is_null());
    let busy = second.ask(json!({"action":"call_start", "argument":session}));
    assert!(
        !busy["error"].is_null(),
        "the selected sibling occupies the user: {busy}"
    );

    second.ask(json!({"action":"call_decline", "argument":session, "call_id":call_id}));
    assert_eq!(
        caller.ask(json!({"action":"dm_poll", "argument":session}))["active_call"]["call_id"],
        *call_id
    );
    assert_eq!(
        first.ask(json!({"action":"dm_poll", "argument":session}))["active_call"]["call_id"],
        *call_id
    );
    caller.ask(json!({"action":"call_end", "argument":session, "call_id":call_id}));
    wait_call_view(&mut first, session, |view| view["active_call"].is_null());
    let next = first.ask(json!({"action":"call_start", "argument":session}));
    assert!(
        next["error"].is_null(),
        "an ended call must release account occupancy: {next}"
    );
    first.ask(json!({"action":"call_end", "argument":session, "call_id":next["call_id"]}));
}

fn wait_call_view(
    peer: &mut Peer,
    session: &str,
    ready: impl Fn(&serde_json::Value) -> bool,
) -> serde_json::Value {
    let until = std::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        let sessions = peer.ask(json!({"action":"dm_list"}));
        if let Some(view) = sessions["sessions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|view| view["session_id"] == session && ready(view))
        {
            return view.clone();
        }
        assert!(
            std::time::Instant::now() < until,
            "call state did not converge: {sessions}"
        );
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
}

#[test]
fn rejected_call_start_keeps_the_api_peer_available() {
    let _network = isolated_network_scenario();
    let mut peer = Peer::new_api();
    let result = peer.ask(json!({"action":"call_start", "argument":"missing-session"}));
    assert_eq!(result["error"], "MissingConversation");
    assert!(peer.ask(json!({"action":"snapshot"}))["devices"].is_array());
}
