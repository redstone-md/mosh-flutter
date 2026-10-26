use super::*;

#[test]
fn an_erased_record_does_not_block_remaining_history_or_restore_deleted_bytes() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    returning.stop();
    author.ask(
        json!({"action":"chat_send","kind":"group","argument":id,"body":"erase this content"}),
    );
    let sent = wait_text(&mut [&mut author, &mut holder], &id);
    author.ask(json!({"action":"chat_delete","kind":"group","argument":id,
        "message_id":sent["messages"][0]["message_id"]}));
    let deadline = Instant::now() + Duration::from_secs(90);
    while !poll(&mut holder, &id)["messages"][0]["body"]
        .as_str()
        .is_some_and(str::is_empty)
    {
        poll(&mut author, &id);
        assert!(Instant::now() < deadline, "shared erasure did not converge");
        std::thread::sleep(Duration::from_millis(50));
    }
    author
        .ask(json!({"action":"chat_send","kind":"group","argument":id,"body":"retained content"}));
    while !poll(&mut holder, &id)["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|message| message["body"] == "retained content")
    {
        poll(&mut author, &id);
        assert!(
            Instant::now() < deadline,
            "holder did not retain later content"
        );
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
            .any(|message| message["body"] == "erase this content"));
        if snapshot["history_sync"]["state"] == "complete" {
            assert!(snapshot["messages"]
                .as_array()
                .unwrap()
                .iter()
                .any(|message| message["body"] == "retained content"));
            break;
        }
        assert!(
            Instant::now() < deadline,
            "retained history blocked by erased row: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}
