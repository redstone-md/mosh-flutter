use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

#[test]
fn maximum_packet_can_refill_depleted_budgets_before_expiring() {
    for relayed in [false, true] {
        for priority in [false, true] {
            let started = Instant::now();
            let limits = capacity(relayed);
            let mut queue = Queue {
                relayed,
                ..Default::default()
            };
            let bytes = super::super::library::MAX_PACKET + 20;
            queue.lane(priority).push_back(Packet {
                peer: "remote".into(),
                bytes: vec![1; bytes],
                queued: started,
            });
            let mut total = Budget::new(limits.total_bytes_per_second, started);
            let mut video = Budget::new(limits.video_bytes_per_second, started);
            assert!(matches!(
                queue.next(&mut total, &mut video, started),
                Next::Wait(_)
            ));
            let rate = if priority {
                limits.total_bytes_per_second
            } else {
                limits.video_bytes_per_second
            };
            let refilled = started
                + Duration::from_secs_f64(bytes as f64 / rate as f64)
                + Duration::from_millis(1);
            assert!(matches!(
                queue.next(&mut total, &mut video, refilled),
                Next::Send(_)
            ));
            assert_eq!(queue.dropped, 0);
        }
    }
}

#[test]
fn video_bursts_fit_the_direct_and_relay_queue_deadlines() {
    for relayed in [true, false] {
        let started = Instant::now();
        let mut now = started + Duration::from_millis(120);
        let limits = capacity(relayed);
        let mut total = Budget::new(limits.total_bytes_per_second, started);
        let mut video = Budget::new(limits.video_bytes_per_second, started);
        let mut queue = Queue {
            relayed,
            ..Default::default()
        };
        for sequence in 0..4 {
            queue.video.push_back(Packet {
                peer: "remote".into(),
                bytes: vec![sequence; 1020],
                queued: now,
            });
        }
        let mut packets = Vec::new();
        while !queue.video.is_empty() {
            match queue.next(&mut total, &mut video, now) {
                Next::Send(packet) => packets.push(packet),
                Next::Wait(wait) => now += wait + Duration::from_micros(1),
            }
        }
        assert_eq!(
            packets.len(),
            4,
            "one missing fragment loses the video frame"
        );
        assert_eq!(queue.dropped, 0);
        for (sequence, packet) in packets.iter().enumerate() {
            assert_eq!(packet.bytes, vec![sequence as u8; 1020]);
        }
    }
}

#[test]
fn waiting_video_preserves_capacity_for_audio_and_control() {
    let started = Instant::now();
    let mut queue = Queue {
        relayed: true,
        ..Default::default()
    };
    let mut total = Budget::new(48_000, started);
    let mut video = Budget::new(32_000, started);
    queue.video.push_back(Packet {
        peer: "remote".into(),
        bytes: vec![1; 1400],
        queued: started,
    });
    assert!(matches!(
        queue.next(&mut total, &mut video, started),
        Next::Wait(_)
    ));
    queue.priority.push_back(Packet {
        peer: "remote".into(),
        bytes: vec![2; 16],
        queued: started,
    });
    let Next::Send(audio) = queue.next(&mut total, &mut video, started + Duration::from_millis(1))
    else {
        panic!("available audio capacity cannot be spent by waiting video");
    };
    assert_eq!(audio.bytes, vec![2; 16]);
    assert_eq!(video.available, 0.0);
    let Next::Send(frame) = queue.next(&mut total, &mut video, started + Duration::from_millis(44))
    else {
        panic!("video must remain queued until both budgets are available");
    };
    assert_eq!(frame.bytes, vec![1; 1400]);
    assert_eq!(queue.dropped, 0);
}

#[test]
fn packets_older_than_the_queue_deadline_are_never_sent() {
    let now = Instant::now();
    let mut queue = Queue::default();
    queue.video.push_back(Packet {
        peer: "remote".into(),
        bytes: vec![0; 100],
        queued: now - Duration::from_millis(101),
    });
    let next = queue.next(
        &mut Budget::new(48_000, now),
        &mut Budget::new(32_000, now),
        now,
    );
    assert!(matches!(next, Next::Wait(Duration::ZERO)));
    assert!(queue.video.is_empty());
    assert_eq!(queue.dropped, 1);
}

#[test]
fn transport_refusal_is_reported_without_requeueing() {
    let net = MemoryNet::new();
    let sender = Sender::new(net.endpoint("local"));
    sender.enqueue("missing", &[9; 16], &[2; 16], true);
    let deadline = Instant::now() + Duration::from_secs(1);
    while sender.dropped() == 0 {
        assert!(
            Instant::now() < deadline,
            "transport refusal was not observed"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(sender.dropped(), 1);
}

#[cfg(feature = "native-media-tests")]
mod native {
    use super::*;
    use crate::native_call::{
        library::{Engine, MAX_PACKET},
        types::Binding,
    };
    use crate::private_dm_runtime::transport::PeerTransport;
    use serde_json::json;

    #[test]
    #[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
    fn relay_video_does_not_lose_fresh_decoded_frames() {
        let _priority = crate::native_call::media_thread::Priority::new();
        let net = MemoryNet::new();
        let a = net.endpoint("a");
        let b = net.endpoint("b");
        net.link_both("a", "b", PeerTransport::Relayed);
        let sending = Sender::new(a.clone());
        let returning = Sender::new(b.clone());
        sending.relayed(true);
        returning.relayed(true);
        let mut pixels = vec![0; 640 * 360 * 4];
        pattern(&mut pixels, 0);
        let mut decoded_pixels = vec![0; pixels.len()];
        let (mut caller, mut callee) = pair();
        let started = Instant::now();
        let mut captured = started;
        let mut decoded = started;
        let mut sequence = 0;
        let mut tick = 0;
        while started.elapsed() < Duration::from_secs(8) {
            if captured.elapsed() >= Duration::from_millis(66) {
                captured = Instant::now();
                motion(&mut pixels, tick);
                assert!(caller.push(640, 360, &pixels));
                tick += 1;
            }
            forward(&mut caller, &mut callee, &sending, "b", &*a);
            forward(&mut callee, &mut caller, &returning, "a", &*b);
            if let Some(frame) = callee.frame(sequence, &mut decoded_pixels) {
                sequence = frame.sequence;
                decoded = Instant::now();
            }
            assert_fresh(sequence, decoded, &sending, &mut caller, &mut callee);
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(
            sequence >= 30,
            "remote video stalled: {sequence} decoded; {} packets lost",
            sending.dropped()
        );
    }

    fn assert_fresh(
        sequence: u64,
        decoded: Instant,
        sender: &Sender,
        caller: &mut Engine,
        callee: &mut Engine,
    ) {
        assert!(
            sequence == 0 || decoded.elapsed() < Duration::from_secs(1),
            "remote video expired at frame {sequence}; lost packets: {}; sender: {}; receiver: {}",
            sender.dropped(),
            caller.ask(json!({"action":"snapshot"})).unwrap(),
            callee.ask(json!({"action":"snapshot"})).unwrap()
        );
    }

    fn pair() -> (Engine, Engine) {
        let binding = Binding {
            session_id: "dm".into(),
            call_id: "call".into(),
            caller: "a".into(),
            callee: "b".into(),
            media_session: vec![9; 16],
        };
        let mut caller = Engine::new(&binding, true).unwrap();
        let mut callee = Engine::new(&binding, false).unwrap();
        let offer = caller.ask(json!({"action":"offer"})).unwrap();
        let answer = callee
            .ask(json!({"action":"remote", "description":offer}))
            .unwrap();
        caller
            .ask(json!({"action":"remote", "description":answer}))
            .unwrap();
        caller
            .ask(json!({"action":"choices", "microphone":false, "video":true}))
            .unwrap();
        for engine in [&mut caller, &mut callee] {
            engine.ask(json!({"action":"start"})).unwrap();
            engine
                .ask(json!({"action":"budget", "max_bps":capacity(true).encoder_bits_per_second}))
                .unwrap();
        }
        (caller, callee)
    }

    fn forward(
        from: &mut Engine,
        to: &mut Engine,
        sender: &Sender,
        peer: &str,
        receive: &dyn DmTransport,
    ) {
        let gathered = from.ask(json!({"action":"tick"})).unwrap();
        to.ask(json!({"action":"tick", "candidates":gathered["candidates"]}))
            .unwrap();
        for message in receive.drain_call_packets() {
            assert!(from.receive(unwrap(&message.payload, &[9; 16]).unwrap()));
        }
        let mut packet = [0; MAX_PACKET];
        while let Some(length) = from.packet(&mut packet) {
            sender.enqueue(
                peer,
                &[9; 16],
                &packet[..length],
                from.priority(&packet[..length]),
            );
        }
    }

    fn pattern(pixels: &mut [u8], tick: usize) {
        for (index, pixel) in pixels.chunks_exact_mut(4).enumerate() {
            let x = index % 640;
            let y = index / 640;
            let detail =
                (x as u32).wrapping_mul(2_654_435_761) ^ (y as u32).wrapping_mul(1_013_904_223);
            if (240..400).contains(&x) && (120..240).contains(&y) {
                pixel.copy_from_slice(&[(tick * 7) as u8, (tick * 13) as u8, 128, 255]);
            } else {
                pixel.copy_from_slice(&[
                    (detail >> 16) as u8,
                    (detail >> 8) as u8,
                    detail as u8,
                    255,
                ]);
            }
        }
    }

    fn motion(pixels: &mut [u8], tick: usize) {
        for row in pixels.chunks_exact_mut(640 * 4).skip(120).take(120) {
            for pixel in row[240 * 4..400 * 4].chunks_exact_mut(4) {
                pixel.copy_from_slice(&[(tick * 7) as u8, (tick * 13) as u8, 128, 255]);
            }
        }
    }
}
