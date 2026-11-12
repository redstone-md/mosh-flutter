//! When a text's writes reach the disk, and what leaves before they do.
use super::super::state_tests::payload_says;
use super::*;
use std::sync::Mutex;

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

#[test]
fn a_text_whose_ratchet_the_receiver_could_not_save_is_not_acknowledged_until_it_is() {
    let mut pair = Pair::new("unsaved-ratchet");
    let fault = pair.bob_store.refuse_dm_snapshot_writes();
    pair.alice
        .send_message(&pair.session_id, "save my key before the receipt".into())
        .unwrap();

    pair.bob.service();

    assert_eq!(delivery(&mut pair), Some(MessageDeliveryStatus::Sent));
    drop(fault);
    pair.bob.service();
    assert_eq!(delivery(&mut pair), Some(MessageDeliveryStatus::Delivered));
}

/// How many times `store` had synced when the first frame `named` left
/// `from` for `to`.
fn syncs_as_it_leaves(
    pair: &Pair,
    (from, to): (&str, &str),
    store: &Arc<Persistence>,
    named: impl Fn(&str, &[u8]) -> bool + Send + Sync + 'static,
) -> Arc<Mutex<Option<u64>>> {
    let seen = Arc::new(Mutex::new(None));
    let (noted, store) = (seen.clone(), store.clone());
    pair.net.drop_frames(from, to, move |channel, payload| {
        if named(channel, payload) {
            noted.lock().unwrap().get_or_insert(store.syncs());
        }
        false
    });
    seen
}

#[test]
fn a_text_syncs_its_sender_s_disk_three_times_and_its_receiver_s_once() {
    let mut pair = Pair::new("syncs");
    // Whatever the handshake left unsaved is down before the count starts.
    pair.alice.service();
    pair.bob.service();
    let (alice, bob) = (pair.store.syncs(), pair.bob_store.syncs());
    let text = syncs_as_it_leaves(&pair, (ALICE_ID, BOB_ID), &pair.store, |channel, _| {
        channel.starts_with(DATA_CHANNEL_PREFIX)
    });
    let receipt = syncs_as_it_leaves(&pair, (BOB_ID, ALICE_ID), &pair.bob_store, |_, payload| {
        payload_says(payload, "DeliveryAck")
    });

    pair.alice
        .send_message(&pair.session_id, "count my syncs".into())
        .unwrap();
    // One before the text leaves, one at the command's end.
    assert_eq!(*text.lock().unwrap(), Some(alice + 1));
    assert_eq!(pair.store.syncs(), alice + 2);

    pair.bob.service();
    // The text, the ratchet that opened it and the one that sealed its
    // receipt go down together, before the receipt leaves.
    assert_eq!(*receipt.lock().unwrap(), Some(bob + 1));
    assert_eq!(pair.bob_store.syncs(), bob + 1);

    pair.alice.service();
    assert_eq!(delivery(&mut pair), Some(MessageDeliveryStatus::Delivered));
    assert_eq!(pair.store.syncs(), alice + 3);
}

#[test]
fn the_ratchet_that_sealed_a_receipt_is_on_disk_once_the_receipt_has_left() {
    let mut pair = Pair::new("receipt-ratchet");
    pair.bob
        .send_message(&pair.session_id, "acknowledge me".into())
        .unwrap();

    pair.alice.service();

    // A restart from an older ratchet seals its next frame with the
    // receipt's key, which Bob has already spent.
    let sealed_with = pair.alice.sessions[pair.session_id.as_str()]
        .crypto
        .snapshot();
    assert_eq!(
        pair.store.get_mls_snapshot(&pair.session_id).unwrap(),
        Some(sealed_with)
    );
}

#[test]
fn a_frame_that_seals_nothing_after_a_save_writes_nothing() {
    let mut pair = Pair::new("quiet-frame");
    // The tick opened frames, so the first announcement saves their ratchet.
    pair.alice.service();
    let announce = |pair: &Pair| {
        pair.alice.sessions[pair.session_id.as_str()]
            .publish_peer_announce()
            .unwrap();
    };
    let before = pair.store.syncs();
    announce(&pair);
    assert_eq!(pair.store.syncs(), before + 1);

    announce(&pair);

    assert_eq!(pair.store.syncs(), before + 1);
}
