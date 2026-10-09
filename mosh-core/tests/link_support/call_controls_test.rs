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

#[test]
#[ignore = "Prepare native media and set MOSH_MEDIA_ENGINE before running this real-process test"]
fn native_selected_pair_connects_over_moss_without_capture() {
    let _network = isolated_network_scenario();
    let (mut caller, mut receiver, session, id) = native_pair(false);
    let session = session.as_str();
    let id = &id;
    let until = std::time::Instant::now() + std::time::Duration::from_secs(20);
    loop {
        let views: Vec<_> = [&mut caller, &mut receiver]
            .into_iter()
            .map(|peer| {
                peer.ask(json!({"action":"call_native_snapshot","argument":session,"call_id":id}))
            })
            .collect();
        if views.iter().all(|view| view["ready"] == true) {
            for view in views {
                assert_eq!(view["microphone"], false);
                assert_eq!(view["camera"], false);
            }
            break;
        }
        assert!(
            std::time::Instant::now() < until,
            "native setup failed: {views:?}"
        );
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    caller.ask(json!({"action":"call_end","argument":session,"call_id":id}));
    wait_call_view(&mut receiver, session, |view| view["active_call"].is_null());
    let status =
        receiver.ask(json!({"action":"call_native_snapshot","argument":session,"call_id":id}));
    assert!(status.is_null());
}

fn native_pair(camera: bool) -> (Peer, Peer, String, serde_json::Value) {
    native_pair_prepared(camera, true)
}

fn native_pair_prepared(
    camera: bool,
    prepare_caller: bool,
) -> (Peer, Peer, String, serde_json::Value) {
    let (mut caller, mut receiver) = (Peer::new_api(), Peer::new_api());
    let invite = caller.ask(json!({"action":"dm_invite"}));
    receiver.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    let session = invite["session_id"].as_str().unwrap();
    caller.ask(json!({"action":"dm_send","argument":session,"body":"Native call ready"}));
    receiver.wait_dm_text(session, "Native call ready");
    let call = caller.ask(json!({"action":"call_start","argument":session}));
    let id = call["call_id"].clone();
    wait_call_view(&mut receiver, session, |view| {
        view["pending_call"]["call_id"] == id
    });
    receiver.ask(json!({"action":"call_accept","argument":session,"call_id":id}));
    for (peer, camera, prepare) in [
        (&mut caller, camera, prepare_caller),
        (&mut receiver, false, true),
    ] {
        wait_call_view(peer, session, |view| view["active_call"]["call_id"] == id);
        if !prepare {
            continue;
        }
        let prepared = peer.ask(
            json!({"action":"call_native_prepare","argument":session,"call_id":id,"camera":camera}),
        );
        assert!(prepared["error"].is_null(), "{prepared}");
    }
    (caller, receiver, session.to_owned(), id)
}

#[test]
#[ignore = "Requires native media and the compiled test camera driver"]
fn native_camera_frames_cross_moss_and_camera_off_preserves_the_call() {
    let _network = isolated_network_scenario();
    let (mut caller, mut receiver, session, id) = native_pair(true);
    let until = std::time::Instant::now() + std::time::Duration::from_secs(20);
    let first = loop {
        let frame =
            receiver.ask(json!({"action":"call_native_frame","argument":session,"call_id":id}));
        if frame["sequence"]
            .as_u64()
            .is_some_and(|sequence| sequence > 20)
        {
            break frame;
        }
        assert!(
            std::time::Instant::now() < until,
            "remote video never decoded: {frame}"
        );
        std::thread::sleep(std::time::Duration::from_millis(100));
    };
    assert_eq!(first["width"], 320);
    assert_eq!(first["height"], 180);
    assert_eq!(first["rgba_bytes"], 320 * 180 * 4);
    assert_eq!(first["first_pixel"][3], 255);
    let later = loop {
        let frame =
            receiver.ask(json!({"action":"call_native_frame","argument":session,"call_id":id}));
        if frame["sequence"].as_u64() > first["sequence"].as_u64() {
            break frame;
        }
        assert!(std::time::Instant::now() < until, "frame sequence stalled");
        std::thread::sleep(std::time::Duration::from_millis(50));
    };
    assert_ne!(
        first["first_pixel"], later["first_pixel"],
        "the displayed video must change"
    );
    let off =
        caller.ask(json!({"action":"call_native_camera_off","argument":session,"call_id":id}));
    assert!(off["error"].is_null(), "camera off failed: {off}");
    std::thread::sleep(std::time::Duration::from_secs(2));
    assert!(receiver
        .ask(json!({"action":"call_native_frame","argument":session,"call_id":id}))
        .is_null());
    for peer in [&mut caller, &mut receiver] {
        let view =
            peer.ask(json!({"action":"call_native_snapshot","argument":session,"call_id":id}));
        assert_eq!(
            view["ready"], true,
            "camera off cannot stop receiving: {view}"
        );
        assert_eq!(view["camera"], false);
        assert_eq!(view["camera_requested"], false);
    }
    caller.ask(json!({"action":"call_end","argument":session,"call_id":id}));
    wait_call_view(&mut receiver, &session, |view| {
        view["active_call"].is_null()
    });
}

#[test]
#[ignore = "Requires native media and the compiled stalled camera-driver fixture"]
fn native_stalled_camera_releases_capture_without_ending_receive_only_media() {
    let _network = isolated_network_scenario();
    let (mut caller, mut receiver, session, id) = native_pair(false);
    let result =
        caller.ask(json!({"action":"call_native_camera_stall","argument":session,"call_id":id}));
    assert!(result["error"].is_null(), "{result}");
    let until = std::time::Instant::now() + std::time::Duration::from_secs(20);
    loop {
        let status =
            caller.ask(json!({"action":"call_native_snapshot","argument":session,"call_id":id}));
        if status["camera_failed"] == true && status["ready"] == true {
            assert_eq!(status["camera_requested"], false);
            assert_eq!(status["camera"], false);
            assert_eq!(status["failed"], false);
            break;
        }
        assert!(
            std::time::Instant::now() < until,
            "stalled camera harmed the call: {status}"
        );
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    let status =
        receiver.ask(json!({"action":"call_native_snapshot","argument":session,"call_id":id}));
    assert_eq!(status["ready"], true);
    caller.ask(json!({"action":"call_end","argument":session,"call_id":id}));
}

#[test]
#[ignore = "Requires the native owner; tests a selected caller that never starts negotiation"]
fn native_missing_offer_ends_both_selected_calls_after_setup_timeout() {
    let _network = isolated_network_scenario();
    let (mut caller, mut receiver, session, _id) = native_pair_prepared(false, false);
    // The owner tests its exact 15-second deadline with a controlled clock.
    // This process test allows both DM owners to observe and persist termination.
    wait_call_view(&mut receiver, &session, |view| {
        view["active_call"].is_null()
    });
    wait_call_view(&mut caller, &session, |view| view["active_call"].is_null());
}
