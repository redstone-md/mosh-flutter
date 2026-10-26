use super::{coordinator::Coordinator, wire::HistoryFrame};

fn frame(bytes: usize) -> HistoryFrame {
    HistoryFrame {
        version: 1,
        conversation: "channel:bounded".into(),
        mesh_id: "channel/bounded".into(),
        channel: "channel-blob/bounded".into(),
        sender_key: "11".repeat(32),
        recipient_key: Some("22".repeat(32)),
        request_id: "00".repeat(16),
        round: 1,
        payload_b64: "x".repeat(bytes),
        signature: "11".repeat(64),
    }
}

#[test]
fn idle_retry_backs_off_and_peer_or_history_changes_only_wake_after_coalescing() {
    let mut coordinator = Coordinator::default();
    let mut now = 100_000;
    for (minimum, maximum) in [
        (5000, 6000),
        (10000, 12000),
        (20000, 24000),
        (40000, 48000),
        (60000, 60000),
        (60000, 60000),
    ] {
        assert!(coordinator.probe_due(now));
        coordinator.probed(now);
        assert!(!coordinator.probe_due(now + minimum - 1));
        assert!(coordinator.probe_due(now + maximum));
        now += maximum;
    }
    coordinator.probed(now);
    coordinator.observe(1, 0);
    assert!(!coordinator.probe_due(now + 1999));
    assert!(coordinator.probe_due(now + 2000));
    coordinator.probed(now + 2000);
    coordinator.observe(1, 0);
    assert!(
        !coordinator.probe_due(now + 4000),
        "an unchanged view cannot keep resetting the delay"
    );
    coordinator.observe(1, 1);
    assert!(coordinator.probe_due(now + 4000));
}

#[test]
fn an_inbox_obeys_both_its_frame_and_aggregate_byte_budgets() {
    let mut coordinator = Coordinator::default();
    for _ in 0..40 {
        coordinator.queue(frame(0)).unwrap();
    }
    assert_eq!(coordinator.drain().len(), 32);
    for _ in 0..40 {
        coordinator.queue(frame(60_000)).unwrap();
    }
    let received = coordinator.drain();
    assert_eq!(received.len(), 17);
    assert!(
        received
            .iter()
            .map(|frame| serde_json::to_vec(frame).unwrap().len())
            .sum::<usize>()
            <= 1024 * 1024
    );
    for _ in 0..32 {
        coordinator.queue(frame(0)).unwrap();
    }
    assert_eq!(
        coordinator.drain().len(),
        32,
        "draining releases the bounded byte budget"
    );
}
