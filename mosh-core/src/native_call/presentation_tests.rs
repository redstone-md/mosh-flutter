//! Frames leave Rust at the size the window shows them, while the encoder
//! still takes the whole camera.
use super::native::{forward, pair};
use super::*;
use crate::native_call::{
    capture::{Captured, Prepared},
    state::State,
    types::{Context, Surface},
    Hub,
};
use crate::private_dm_runtime::transport::PeerTransport;
use serde_json::json;
use std::sync::{Arc, Mutex};

const THUMBNAIL: Surface = Surface {
    width: 320,
    height: 320,
};

fn presenting() -> State {
    State {
        context: Some(Context {
            session_id: "dm".into(),
            call_id: "call".into(),
            superseded: None,
            active: true,
            caller: true,
            caller_signer: "a".into(),
            callee_signer: Some("b".into()),
            peer: "b".into(),
        }),
        prepared: true,
        ..Default::default()
    }
}

const LUMA: usize = 1280 * 720;

/// A 1280x720 I420 capture prepared for `surface`, as the owner does before it locks.
fn capture(sequence: u64, planes: &[u8], surface: Surface) -> Prepared {
    let frame = Captured {
        sequence,
        width: 1280,
        height: 720,
        planes: planes.to_vec(),
        received: Instant::now(),
        source_age_ms: 0,
    };
    Prepared::new(0, Arc::new(frame), surface)
}

fn preview(state: &Mutex<State>, sequence: u64, planes: &[u8]) {
    let surface = state.lock().unwrap().surfaces[0];
    capture(sequence, planes, surface).present(&mut state.lock().unwrap(), None);
}

#[test]
fn local_preview_reaches_the_window_at_its_surface_size() {
    let state = Arc::new(Mutex::new(presenting()));
    let hub = Hub {
        state: state.clone(),
    };
    // BT.601 video range for RGB (220, 30, 30).
    let red = [vec![91; LUMA], vec![100; LUMA / 4], vec![211; LUMA / 4]].concat();
    preview(&state, 1, &red);
    let whole = hub.frame("dm", "call", true, 0).unwrap();
    assert_eq!((whole.width, whole.height), (1280, 720), "no surface yet");
    hub.show_at(THUMBNAIL, Surface::default()).unwrap();
    preview(&state, 2, &red);
    let shown = hub.frame("dm", "call", true, whole.sequence).unwrap();
    assert_eq!(
        (shown.width, shown.height, shown.pixels.len()),
        (320, 180, 320 * 180 * 4)
    );
    assert!(
        shown.pixels[0] > 180 && shown.pixels[1] < 70,
        "colors were lost"
    );
}

#[test]
// test-policy: skip MOSH-86 -- drives two real engines loaded from MOSH_MEDIA_ENGINE
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn a_thumbnail_preview_still_sends_the_whole_camera() {
    let net = MemoryNet::new();
    let a = net.endpoint("a");
    let b = net.endpoint("b");
    net.link_both("a", "b", PeerTransport::Direct);
    let (sending, returning) = (Sender::new(a), Sender::new(b));
    let (mut caller, mut callee) = pair(
        false,
        sending.link("b", &[9; 16]),
        returning.link("a", &[9; 16]),
    );
    let mut state = presenting();
    state.surfaces[0] = THUMBNAIL;
    let mut planes: Vec<u8> = (0..LUMA * 3 / 2).map(|i| (i % 251) as u8).collect();
    let started = Instant::now();
    let mut camera = 0;
    let mut sequence = 0;
    while camera < 1280 && started.elapsed() < Duration::from_secs(10) {
        sequence += 1;
        planes[..1280 * 90].fill((sequence * 9) as u8);
        capture(sequence, &planes, state.surfaces[0]).present(&mut state, Some(&caller));
        forward(&mut caller, &mut callee);
        forward(&mut callee, &mut caller);
        let snapshot = caller.ask(json!({"action":"snapshot"})).unwrap();
        camera = snapshot["camera"]["width"].as_u64().unwrap_or(0);
        // test-policy: wait MOSH-86 -- a real camera cadence; libwebrtc encodes on its own clock
        std::thread::sleep(Duration::from_millis(33));
    }
    // libwebrtc may still lower what it encodes under load or a cold
    // bandwidth estimate; its source must receive the whole camera.
    assert_eq!(
        camera, 1280,
        "the encoder's source never got the 720p camera"
    );
    let preview = &state.frames[0].as_ref().unwrap().frame;
    assert_eq!((preview.width, preview.height), (320, 180));
}

#[test]
// test-policy: skip MOSH-96 -- drives two real engines loaded from MOSH_MEDIA_ENGINE
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn a_frame_the_encoder_refuses_is_not_live_camera_video() {
    let net = MemoryNet::new();
    let (a, b) = (net.endpoint("a"), net.endpoint("b"));
    net.link_both("a", "b", PeerTransport::Direct);
    let (sending, returning) = (Sender::new(a), Sender::new(b));
    let (caller, _callee) = pair(
        false,
        sending.link("b", &[9; 16]),
        returning.link("a", &[9; 16]),
    );
    let mut state = presenting();
    // No engine takes a frame whose planes do not match its size.
    let truncated = Captured {
        sequence: 1,
        width: 1280,
        height: 720,
        planes: vec![0; LUMA],
        received: Instant::now(),
        source_age_ms: 0,
    };
    Prepared::new(0, Arc::new(truncated), Surface::default()).present(&mut state, Some(&caller));
    assert!(!state.snapshot.camera, "the peer would be told of video");
    capture(2, &vec![0; LUMA * 3 / 2], Surface::default()).present(&mut state, Some(&caller));
    assert!(state.snapshot.camera);
}
