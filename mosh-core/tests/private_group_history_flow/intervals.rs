use super::*;

#[test]
fn rejoining_preserves_earlier_entitlement_and_excludes_the_absence_interval() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    author.ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"earlier eligible interval"}));
    wait_text(&mut [&mut holder, &mut returning], &id);
    let invite = poll(&mut author, &id)["invite_uri"].clone();
    returning.ask(json!({"action":"chat_leave","kind":"group","argument":id}));
    let deadline = Instant::now() + Duration::from_secs(90);
    while [&mut author, &mut holder]
        .into_iter()
        .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
        .any(|count| count != 2)
    {
        assert!(Instant::now() < deadline, "departure did not converge");
        std::thread::sleep(Duration::from_millis(50));
    }
    author.ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"during absence"}));
    while !poll(&mut holder, &id)["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|message| message["body"] == "during absence")
    {
        poll(&mut author, &id);
        assert!(
            Instant::now() < deadline,
            "holder did not retain absence record"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
    returning.ask(json!({"action":"chat_join","kind":"group","argument":invite}));
    while [&mut author, &mut holder, &mut returning]
        .into_iter()
        .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
        .any(|count| count != 3)
    {
        assert!(Instant::now() < deadline, "rejoin did not converge");
        std::thread::sleep(Duration::from_millis(50));
    }
    author.stop();
    holder.restart();
    returning.restart();
    loop {
        poll(&mut holder, &id);
        let snapshot = poll(&mut returning, &id);
        assert!(!snapshot["messages"]
            .as_array()
            .unwrap()
            .iter()
            .any(|message| message["body"] == "during absence"));
        if snapshot["history_sync"]["state"] == "complete" {
            assert_eq!(snapshot["messages"].as_array().unwrap().len(), 1);
            assert_eq!(snapshot["messages"][0]["body"], "earlier eligible interval");
            break;
        }
        assert!(
            Instant::now() < deadline,
            "rejoin earlier history incomplete: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn an_ordinary_holder_replays_missing_membership_before_history() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    returning.stop();
    let mut newcomer = Peer::new_api();
    newcomer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    let state = poll(&mut author, &id);
    newcomer.ask(json!({"action":"chat_join","kind":"group","argument":state["invite_uri"]}));
    let deadline = Instant::now() + Duration::from_secs(90);
    while [&mut author, &mut holder, &mut newcomer]
        .into_iter()
        .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
        .any(|count| count != 4)
    {
        assert!(Instant::now() < deadline, "new membership did not converge");
        std::thread::sleep(Duration::from_millis(50));
    }
    author.ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"after offline membership transition"}));
    wait_text(&mut [&mut holder], &id);
    author.stop();
    newcomer.stop();
    holder.restart();
    returning.restart();
    let recovered = wait_text(&mut [&mut holder, &mut returning], &id);
    assert_eq!(recovered["member_count"], 4);
    assert_eq!(
        recovered["messages"][0]["body"],
        "after offline membership transition"
    );
    assert_eq!(recovered["history_sync"]["state"], "complete");
}

#[test]
fn a_new_member_gets_postjoin_history_without_prejoin_content() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut existing, id) = three_members();
    author
        .ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"before admission"}));
    wait_text(&mut [&mut holder, &mut existing], &id);
    let mut newcomer = Peer::new_api();
    newcomer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    let state = poll(&mut author, &id);
    newcomer.ask(json!({"action":"chat_join","kind":"group","argument":state["invite_uri"]}));
    let deadline = Instant::now() + Duration::from_secs(90);
    while [&mut author, &mut holder, &mut newcomer]
        .into_iter()
        .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
        .any(|count| count != 4)
    {
        assert!(Instant::now() < deadline, "new membership did not converge");
        std::thread::sleep(Duration::from_millis(50));
    }
    author.ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"after admission"}));
    loop {
        poll(&mut author, &id);
        poll(&mut holder, &id);
        let snapshot = poll(&mut newcomer, &id);
        assert!(!snapshot["messages"]
            .as_array()
            .unwrap()
            .iter()
            .any(|message| message["body"] == "before admission"));
        if snapshot["history_sync"]["state"] == "complete"
            && snapshot["messages"].as_array().unwrap().len() == 1
        {
            assert_eq!(snapshot["messages"][0]["body"], "after admission");
            break;
        }
        assert!(
            Instant::now() < deadline,
            "postjoin recovery did not complete: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}
