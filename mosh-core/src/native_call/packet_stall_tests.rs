//! The engine's outgoing packets keep flowing while the owner step stalls.
use super::native::{forward, pair};
use super::*;
use crate::native_call::library::Sink;
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
    let mut pixels = vec![0; 1280 * 720 * 4];
    let emitted = Arc::new(AtomicUsize::new(0));
    let counted = emitted.clone();
    let mut sink = sending.sink("b", &[9; 16]);
    let counting: Sink = Box::new(move |packet, priority| {
        counted.fetch_add(1, Ordering::Relaxed);
        sink(packet, priority);
    });
    let (mut caller, mut callee) = pair(false, counting, returning.sink("a", &[9; 16]));
    let started = Instant::now();
    let mut tick = 0;
    while started.elapsed() < Duration::from_secs(8) {
        noise(&mut pixels, tick);
        assert!(caller.push(1280, 720, &pixels));
        tick += 1;
        forward(&mut caller, &mut callee, &*a);
        forward(&mut callee, &mut caller, &*b);
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

/// Detail no encoder can compress away, so the call fills its budget.
fn noise(pixels: &mut [u8], tick: usize) {
    let mut state = tick as u64 | 1;
    for chunk in pixels.chunks_exact_mut(8) {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        chunk.copy_from_slice(&state.to_le_bytes());
    }
}
