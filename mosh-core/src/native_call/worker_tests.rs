use super::*;
use crate::native_call::{capture::Captured, library::MAX_PACKET};
use crate::private_dm_runtime::transport::memory::MemoryNet;

#[test]
fn missing_offer_marks_the_call_failed_fifteen_seconds_after_selection() {
    let started = Instant::now();
    let mut context = Context {
        session_id: "dm".into(),
        call_id: "call".into(),
        superseded: None,
        active: false,
        caller: false,
        caller_signer: "caller".into(),
        callee_signer: Some("callee".into()),
        peer: "remote".into(),
    };
    let mut owner = Owner::new(MemoryNet::new().endpoint("local"));
    let mut state = State::default();
    owner.negotiate(&context, &mut state, started).unwrap();
    assert!(!state.snapshot.failed);
    context.active = true;
    let selected = started + Duration::from_secs(60);
    owner.negotiate(&context, &mut state, selected).unwrap();
    assert!(!state.snapshot.failed);
    owner
        .negotiate(&context, &mut state, selected + Duration::from_secs(14))
        .unwrap();
    assert!(!state.snapshot.failed);
    owner
        .negotiate(&context, &mut state, selected + Duration::from_secs(15))
        .unwrap();
    assert!(state.snapshot.failed);
}

#[test]
fn a_frame_prepared_before_the_camera_stops_is_not_presented() {
    let mut owner = Owner::new(MemoryNet::new().endpoint("local"));
    let mut state = State {
        context: Some(outgoing("call")),
        ..Default::default()
    };
    state.snapshot.camera_requested = true; // Turned off since the frame was prepared.
    let frame = Captured {
        sequence: 7,
        width: 2,
        height: 2,
        planes: vec![0; 6],
        received: Instant::now(),
        source_age_ms: 0,
    };
    let prepared = Prepared::new(owner.generation, Arc::new(frame), Surface::default());
    owner.capture(&mut state, Some(prepared)).unwrap();
    assert!(state.frames[0].is_none());
    assert!(!state.snapshot.camera);
    assert_eq!(owner.captured, 0);
}

fn outgoing(call_id: &str) -> Context {
    Context {
        session_id: "dm".into(),
        call_id: call_id.into(),
        superseded: None,
        active: false,
        caller: true,
        caller_signer: "caller".into(),
        callee_signer: None,
        peer: String::new(),
    }
}

#[test]
fn a_new_call_counts_sender_drops_from_zero() {
    let mut owner = Owner::new(MemoryNet::new().endpoint("local"));
    let mut state = State {
        context: Some(outgoing("first")),
        ..Default::default()
    };
    owner.synchronize(&mut state);
    // A relayed video lane drains one maximum packet per ~60 ms, so a burst
    // overflows its 96 slots before the first one leaves.
    let mut wire = owner.sender.link("remote", &[9; 16]);
    for _ in 0..100 {
        wire.send(&[0; MAX_PACKET], false);
    }
    assert!(owner.sender.dropped() > 0);
    state.context = Some(outgoing("second"));
    owner.synchronize(&mut state);
    assert_eq!(owner.sender.dropped(), 0);
}
