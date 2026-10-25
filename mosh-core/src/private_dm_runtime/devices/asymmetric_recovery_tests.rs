use super::super::{state_tests::*, *};
use crate::{device_link::identity::DeviceIdentity, test_temp_directory::TempDirectory};

fn identity(peer: &str) -> (TempDirectory, DeviceIdentity) {
    let dir = TempDirectory::new("mosh-asymmetric-recovery");
    let store =
        Arc::new(Persistence::open_with_dek(&dir.path().join("history.redb"), [73; 32]).unwrap());
    let identity = DeviceIdentity::open(store, peer).unwrap();
    (dir, identity)
}

#[test]
fn an_unchecked_control_cannot_consume_future_text() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.endpoint(ALICE_ID).drain();
    for _ in 0..1250 {
        bob.session_mut(&invite.session_id)
            .unwrap()
            .crypto
            .encrypt(b"lost control")
            .unwrap();
    }
    bob.send_message(&invite.session_id, "genuine future text".into())
        .unwrap();
    let frames = net.endpoint(ALICE_ID).drain();
    let frame = frames
        .iter()
        .find(|frame| frame.channel == data_channel(&invite.session_id))
        .unwrap();
    let data: DataEnvelope = serde_json::from_slice(&frame.payload).unwrap();
    let forged = ControlEnvelope::DeviceIdentity {
        session_id: invite.session_id.clone(),
        participant_id: data.participant_id,
        ciphertext_b64: data.ciphertext_b64,
    };
    let before = alice
        .session_ref(&invite.session_id)
        .unwrap()
        .crypto
        .snapshot();
    net.endpoint(BOB_ID)
        .publish(
            &invite.mesh_id,
            &control_channel(&invite.session_id),
            &serde_json::to_vec(&forged).unwrap(),
        )
        .unwrap();
    alice.receive_inbound();
    assert_eq!(
        alice
            .session_ref(&invite.session_id)
            .unwrap()
            .crypto
            .snapshot(),
        before
    );
    net.endpoint(BOB_ID)
        .publish(&invite.mesh_id, &frame.channel, &frame.payload)
        .unwrap();
    assert!(alice
        .poll_session(&invite.session_id)
        .unwrap()
        .messages
        .iter()
        .any(|message| message.body == "genuine future text"));
}

#[test]
fn independent_contacts_recover_both_directions_after_one_way_loss() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let (_alice_dir, alice_identity) = identity(ALICE_ID);
    let (_bob_dir, bob_identity) = identity(BOB_ID);
    for (runtime, identity) in [(&mut alice, &alice_identity), (&mut bob, &bob_identity)] {
        let session = runtime.session_mut(&invite.session_id).unwrap();
        session.refresh_device_identity(identity).unwrap();
        session.publish_identity_claim(identity);
    }
    connect(&mut alice, &mut bob, &invite.session_id);
    net.fail_streams(BOB_ID, true);
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| true);
    let missed = bob
        .send_message(
            &invite.session_id,
            "desktop text lost during partition".into(),
        )
        .unwrap();
    let start = now_ms();
    for offset in (0..=3_600_000).step_by(2000) {
        for (runtime, identity) in [(&mut alice, &alice_identity), (&mut bob, &bob_identity)] {
            runtime.drain_inbound_at(start + offset);
            runtime
                .session_mut(&invite.session_id)
                .unwrap()
                .publish_identity_claim(identity);
        }
    }
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Handshaking
    );
    assert_eq!(
        state_of(&mut bob, &invite.session_id),
        DmSessionState::Connected
    );
    net.fail_streams(BOB_ID, false);
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| false);
    bob.send_message(&invite.session_id, "desktop to phone".into())
        .unwrap();
    let view = alice.poll_session(&invite.session_id).unwrap();
    assert!(view
        .messages
        .iter()
        .any(|message| message.body == "desktop to phone"));
    assert_eq!(view.state, DmSessionState::Connected);
    alice
        .send_message(&invite.session_id, "phone to desktop".into())
        .unwrap();
    let view = bob.poll_session(&invite.session_id).unwrap();
    assert!(view
        .messages
        .iter()
        .any(|message| message.body == "phone to desktop"));
    // The old in-flight send gets its ordinary next bounded retry, now with
    // fresh ciphertext rather than the discarded pre-recovery generation.
    bob.drain_inbound_at(start + 3_600_000 + AUTO_RESEND_MS);
    let view = alice.poll_session(&invite.session_id).unwrap();
    assert!(view.messages.iter().any(|message| {
        message.body == "phone to desktop"
            && message.delivery_status == Some(MessageDeliveryStatus::Delivered)
    }));
    assert_eq!(
        view.messages
            .iter()
            .filter(|message| { message.body == "desktop text lost during partition" })
            .count(),
        1
    );
    assert_eq!(
        bob.poll_session(&invite.session_id)
            .unwrap()
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(&missed.message_id))
            .unwrap()
            .delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
    let call = alice.call_start(&invite.session_id).unwrap();
    let view = bob.poll_session(&invite.session_id).unwrap();
    assert_eq!(view.pending_call.unwrap().call_id, call.call_id);
}
