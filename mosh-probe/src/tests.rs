use super::*;
use mosh_core::outbound_delivery::MessageDeliveryStatus;

fn send_result(status: MessageDeliveryStatus, error: Option<&str>) -> ChannelSendResult {
    ChannelSendResult {
        name: "probe-channel".to_string(),
        bytes: 0,
        message_id: "m-1".to_string(),
        sent_at_ms: 0,
        delivery_status: status,
        delivery_error: error.map(|e| e.to_string()),
    }
}

/// The exact refusal the runtime hands back (pinned by
/// `no_peers_does_not_count_as_sent`): a Failed send carrying the
/// no-peers text is the signal to re-drive the frame.
#[test]
fn the_no_peers_refusal_is_retryable() {
    let sent = send_result(
        MessageDeliveryStatus::Failed,
        Some("Moss error: no peers yet, so the message did not go out"),
    );
    assert!(refused_for_no_peers(&sent));
}

/// The probe works around exactly that refusal and nothing else. A send
/// that moss accepted, or one that failed for a real transport fault, is
/// not a retry.
#[test]
fn anything_else_is_not_retryable() {
    let accepted = send_result(MessageDeliveryStatus::Sent, None);
    assert!(!refused_for_no_peers(&accepted));

    let pending = send_result(MessageDeliveryStatus::Pending, None);
    assert!(!refused_for_no_peers(&pending));

    let fault = send_result(
        MessageDeliveryStatus::Failed,
        Some("Moss error: publish failed: -1"),
    );
    assert!(!refused_for_no_peers(&fault));

    let refused_text_no_status = send_result(
        MessageDeliveryStatus::Sent,
        Some("Moss error: no peers yet, so the message did not go out"),
    );
    assert!(!refused_for_no_peers(&refused_text_no_status));
}

/// The refusal text cannot drift away from the runtime's wording: this
/// is the string `MossFfiError::NoPeers` renders and the channel runtime
/// regression test pins (ADR 0021).
#[test]
fn the_no_peers_text_matches_the_runtime_display() {
    assert_eq!(
        NO_PEERS_TEXT,
        mosh_core::moss_ffi::MossFfiError::NoPeers.to_string()
    );
}
