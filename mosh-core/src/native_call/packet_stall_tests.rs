//! The engine's packets keep flowing both ways while the owner step stalls.
use super::native::{forward, motion, pair, pattern};
use super::*;
use crate::native_call::{courier::Wire, library::Engine};
use crate::private_dm_runtime::transport::PeerTransport;
use serde_json::json;
use std::sync::atomic::{AtomicUsize, Ordering};

#[test]
// test-policy: skip MOSH-82 -- drives two real engines loaded from MOSH_MEDIA_ENGINE
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn owner_stalls_longer_than_the_packet_age_lose_no_outgoing_video() {
    // The field call lost ~1000 packets in 77 s while the owner step stalled.
    let net = MemoryNet::new();
    let a = net.endpoint("a");
    let b = net.endpoint("b");
    net.link_both("a", "b", PeerTransport::Direct);
    let sending = Sender::new(a.clone());
    let returning = Sender::new(b.clone());
    sending.relayed(false);
    returning.relayed(false);
    let mut planes = vec![0; 1280 * 720 * 3 / 2];
    let emitted = Arc::new(AtomicUsize::new(0));
    let counting = Box::new(Counting {
        wire: sending.link("b", &[9; 16]),
        sent: emitted.clone(),
    });
    let (mut caller, mut callee) = pair(false, counting, returning.link("a", &[9; 16]));
    let started = Instant::now();
    let mut tick = 0;
    while started.elapsed() < Duration::from_secs(8) {
        noise(&mut planes, tick);
        assert!(caller.push(1280, 720, &planes));
        tick += 1;
        forward(&mut caller, &mut callee);
        forward(&mut callee, &mut caller);
        let stall = tick % 25 == 0;
        // test-policy: wait MOSH-82 -- the engine ages packets by wall clock, so the owner stalls in real time
        std::thread::sleep(Duration::from_millis(if stall { 300 } else { 40 }));
    }
    let snapshot = caller.ask(json!({"action":"snapshot"})).unwrap();
    let dropped = &snapshot["queue_dropped"];
    let dropped = dropped["full"].as_u64().unwrap() + dropped["stale"].as_u64().unwrap();
    let emitted = emitted.load(Ordering::Relaxed);
    assert!(
        emitted > 500,
        "{emitted} packets carried too little video: {snapshot}"
    );
    assert!(
        dropped * 100 <= emitted as u64,
        "{dropped} of {emitted} outgoing packets dropped before Moss: {snapshot}"
    );
}

#[test]
// test-policy: skip MOSH-83 -- drives two real engines loaded from MOSH_MEDIA_ENGINE
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn owner_stalls_do_not_hold_back_inbound_video() {
    // The field call's jitter buffers grew while the owner step stalled: in
    // this test, to about 230 ms when inbound packets waited for it and below
    // 140 ms, as without stalls, once they no longer did.
    let net = MemoryNet::new();
    let a = net.endpoint("a");
    let b = net.endpoint("b");
    net.link_both("a", "b", PeerTransport::Direct);
    let sending = Sender::new(a.clone());
    let returning = Sender::new(b.clone());
    sending.relayed(false);
    returning.relayed(false);
    let (mut caller, mut callee) = pair(
        false,
        sending.link("b", &[9; 16]),
        returning.link("a", &[9; 16]),
    );
    let mut planes = vec![0; 640 * 360 * 3 / 2];
    pattern(&mut planes, 0);
    let mut warmed = None;
    for tick in 0..200 {
        motion(&mut planes, tick);
        assert!(caller.push(640, 360, &planes));
        if tick < 75 {
            forward(&mut caller, &mut callee);
            forward(&mut callee, &mut caller);
        } else {
            warmed.get_or_insert_with(|| buffered(&mut callee));
            serve(&mut caller);
            // Every other 480 ms the callee's owner does nothing.
            if tick / 12 % 2 == 0 {
                serve(&mut callee);
            }
        }
        // test-policy: wait MOSH-83 -- libwebrtc buffers by wall clock, so the owner stalls in real time
        std::thread::sleep(Duration::from_millis(40));
    }
    let (before, frames_before) = warmed.unwrap();
    // Statistics refresh at most once a second.
    // test-policy: wait MOSH-83 -- the engine refreshes statistics by wall clock
    std::thread::sleep(Duration::from_secs(1));
    callee.ask(json!({"action":"tick"})).unwrap();
    let (after, frames_after) = buffered(&mut callee);
    let frames = frames_after - frames_before;
    let waited = (after * frames_after as f64 - before * frames_before as f64) / frames as f64;
    assert!(
        frames >= 50 && waited < 200.0,
        "{frames} frames waited {waited:.0} ms on average in the jitter buffer while the owner stalled"
    );
}

/// The video jitter buffer's average delay and the frames it counts, as of
/// the engine's latest statistics.
fn buffered(engine: &mut Engine) -> (f64, u64) {
    let video = &engine.ask(json!({"action":"snapshot"})).unwrap()["video"];
    (
        video["jitter_buffer_ms"].as_f64().unwrap(),
        video["decoded"].as_u64().unwrap(),
    )
}

/// One owner pass that touches no other engine.
fn serve(engine: &mut Engine) {
    engine.ask(json!({"action":"tick"})).unwrap();
}

/// Counts the packets its wire sends.
struct Counting {
    wire: Box<dyn Wire>,
    sent: Arc<AtomicUsize>,
}

impl Wire for Counting {
    fn send(&mut self, packet: &[u8], priority: bool) {
        self.sent.fetch_add(1, Ordering::Relaxed);
        self.wire.send(packet, priority);
    }

    fn receive(&mut self, deliver: &mut dyn FnMut(&[u8])) {
        self.wire.receive(deliver);
    }
}

/// Detail no encoder can compress away, so the call fills its budget.
fn noise(planes: &mut [u8], tick: usize) {
    let mut state = tick as u64 | 1;
    for chunk in planes.chunks_exact_mut(8) {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        chunk.copy_from_slice(&state.to_le_bytes());
    }
}
