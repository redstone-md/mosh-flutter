use super::*;

#[test]
fn a_healthy_holder_repairs_the_exact_offer_lost_by_an_older_group_tail_writer() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    holder.stop();
    returning.stop();
    offer_facts::send_image(&mut author, &id);
    author.restart();
    holder.restart();
    wait_text(&mut [&mut author, &mut holder], &id);
    let original = offer_facts::assert_original_offer(&mut holder, &id, true);
    holder.write_legacy_group_tail(&id);
    author.stop();
    holder.restart();
    let unavailable = poll(&mut holder, &id);
    assert_eq!(unavailable["history_sync"]["state"], "waiting_for_source");
    let damaged = holder.stop_and_inspect_background("group", &id);
    assert_eq!(damaged["messages"][0]["has_preview"], false);
    author.restart();
    holder.restart();
    wait_complete(&mut author, &mut holder, &id);
    let repaired = offer_facts::assert_original_offer(&mut holder, &id, true);
    for field in ["offer_digest", "provenance_digest", "metadata_digest"] {
        assert_eq!(repaired[field], original[field], "changed {field}");
    }
    author.stop();
    holder.restart();
    returning.restart();
    let recovered = wait_text(&mut [&mut holder, &mut returning], &id);
    assert_eq!(recovered["history_sync"]["state"], "complete");
    assert_eq!(recovered["attachments"][0]["state"], "offered");
    assert!(recovered["attachments"][0]["local_path"].is_null());
    assert!(recovered["attachments"][0]["preview_path"].is_null());
    let received = offer_facts::assert_original_offer(&mut returning, &id, true);
    assert_eq!(received["offer_digest"], original["offer_digest"]);
}

fn wait_complete(source: &mut Peer, receiver: &mut Peer, id: &str) {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        poll(source, id);
        let last = poll(receiver, id);
        if last["history_sync"]["state"] == "complete" {
            return;
        }
        assert!(
            Instant::now() < deadline,
            "verified replacement did not complete"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}
