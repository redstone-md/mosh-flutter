//! What a receiver tells its sender before a text's row is saved.
use super::*;

fn delivery(pair: &mut Pair) -> Option<MessageDeliveryStatus> {
    pair.alice.poll_session(&pair.session_id).unwrap().messages[0].delivery_status
}

#[test]
fn a_text_the_receiver_could_not_save_is_not_acknowledged_until_it_is() {
    let mut pair = Pair::new("unsaved-ack");
    let fault = pair.bob_store.refuse_message_writes(DM_HISTORY);
    pair.alice
        .send_message(&pair.session_id, "save me before the receipt".into())
        .unwrap();

    pair.bob.service();

    assert_eq!(delivery(&mut pair), Some(MessageDeliveryStatus::Sent));
    drop(fault);
    pair.bob.service();
    assert_eq!(delivery(&mut pair), Some(MessageDeliveryStatus::Delivered));
}
