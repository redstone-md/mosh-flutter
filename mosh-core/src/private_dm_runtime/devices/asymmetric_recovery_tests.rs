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
    let view = alice.poll_session(&invite.session_id).unwrap();
    assert!(view.messages.iter().any(|message| {
        message.body == "phone to desktop"
            && message.delivery_status == Some(MessageDeliveryStatus::Delivered)
    }));
    let call = alice.call_start(&invite.session_id).unwrap();
    let view = bob.poll_session(&invite.session_id).unwrap();
    assert_eq!(view.pending_call.unwrap().call_id, call.call_id);
}
