//! The engine's side of Moss: the virtual network, `MV1` framing (source
//! port, destination port, UDP payload) and the bounded outgoing queue that
//! mosh-core's egress thread drains with `copy_packet`.
use std::collections::VecDeque;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use std::time::{Duration, Instant};

use libwebrtc::virtual_network::VirtualNetwork;
use serde_json::{Value, json};

pub const MAX_PACKET: usize = 2007;
const MAX_PACKET_AGE: Duration = Duration::from_millis(200);
// 128 in all, split like mosh-core's sender lanes.
const PRIORITY_CAPACITY: usize = 32;
const VIDEO_CAPACITY: usize = 96;
const CALLER_IP: Ipv4Addr = Ipv4Addr::new(192, 0, 2, 1);
const CALLEE_IP: Ipv4Addr = Ipv4Addr::new(192, 0, 2, 2);

pub struct Carrier {
    network: VirtualNetwork,
    peer: Ipv4Addr,
    outgoing: Arc<Outgoing>,
}

impl Carrier {
    pub fn new(caller: bool) -> Self {
        let outgoing = Arc::new(Outgoing::new());
        let queue = outgoing.clone();
        let (ip, peer) = if caller {
            (CALLER_IP, CALLEE_IP)
        } else {
            (CALLEE_IP, CALLER_IP)
        };
        let network = VirtualNetwork::new(ip, move |port, to, data| {
            queue.offer(Instant::now(), encode(port, to.port(), data))
        });
        Self {
            network,
            peer,
            outgoing,
        }
    }

    pub fn network(&self) -> &VirtualNetwork {
        &self.network
    }

    /// The outgoing queue; draining it never waits for the engine.
    pub fn outgoing(&self) -> &Arc<Outgoing> {
        &self.outgoing
    }

    pub fn receive(&self, bytes: &[u8]) -> bool {
        if bytes.len() < 7 || bytes.len() > MAX_PACKET || &bytes[..3] != b"MV1" {
            return false;
        }
        let source = u16::from_be_bytes([bytes[3], bytes[4]]);
        let destination = u16::from_be_bytes([bytes[5], bytes[6]]);
        self.network.receive(
            destination,
            SocketAddrV4::new(self.peer, source),
            &bytes[7..],
        );
        true
    }
}

/// Outgoing packets between libwebrtc's network thread and the egress thread.
/// Audio and control have their own lane, so a video backlog cannot refuse them.
pub struct Outgoing {
    lanes: Mutex<Lanes>,
    full: AtomicU64,
    stale: AtomicU64,
}

type Queued = (Instant, Vec<u8>);

#[derive(Default)]
struct Lanes {
    priority: VecDeque<Queued>,
    video: VecDeque<Queued>,
    audio_payloads: Payloads,
}

struct Payloads([bool; 128]);

impl Default for Payloads {
    fn default() -> Self {
        Self([false; 128])
    }
}

impl Payloads {
    /// True for audio RTP and for everything that is not RTP media (ICE,
    /// DTLS, RTCP), which Moss sends ahead of video.
    fn priority(&self, packet: &[u8]) -> bool {
        let Some(data) = packet.get(7..) else {
            return true;
        };
        if data.len() < 2 || data[0] >> 6 != 2 || (192..=223).contains(&data[1]) {
            return true;
        }
        self.0[usize::from(data[1] & 127)]
    }
}

impl Outgoing {
    fn new() -> Self {
        Self {
            lanes: Mutex::default(),
            full: AtomicU64::new(0),
            stale: AtomicU64::new(0),
        }
    }

    /// Queues one framed packet; false when it is oversized or its lane is full.
    fn offer(&self, queued: Instant, bytes: Vec<u8>) -> bool {
        let mut lanes = self.lanes();
        let priority = lanes.audio_payloads.priority(&bytes);
        let (lane, capacity) = if priority {
            (&mut lanes.priority, PRIORITY_CAPACITY)
        } else {
            (&mut lanes.video, VIDEO_CAPACITY)
        };
        let sent = bytes.len() <= MAX_PACKET && lane.len() < capacity;
        if sent {
            lane.push_back((queued, bytes));
        } else {
            self.full.fetch_add(1, Ordering::Relaxed);
        }
        sent
    }

    /// Packets dropped before Moss: refused by a full lane, or older than
    /// the packet age when drained.
    pub fn dropped(&self) -> Value {
        json!({
            "full": self.full.load(Ordering::Relaxed),
            "stale": self.stale.load(Ordering::Relaxed),
        })
    }

    /// Remembers the audio payload types of the local SDP for `priority`.
    pub fn learn(&self, sdp: &str) {
        let mut lanes = self.lanes();
        let payloads = sdp
            .lines()
            .filter(|line| line.starts_with("m=audio "))
            .flat_map(|line| line.split_ascii_whitespace().skip(3))
            .filter_map(|payload| payload.parse::<usize>().ok());
        for payload in payloads {
            if let Some(audio) = lanes.audio_payloads.0.get_mut(payload) {
                *audio = true;
            }
        }
    }

    pub fn priority(&self, packet: &[u8]) -> bool {
        self.lanes().audio_payloads.priority(packet)
    }

    /// Copies the next fresh packet, audio and control first; -2 when
    /// `buffer` is too small for it.
    pub fn copy_packet(&self, buffer: &mut [u8]) -> i32 {
        let mut lanes = self.lanes();
        loop {
            let lane = if lanes.priority.is_empty() {
                &mut lanes.video
            } else {
                &mut lanes.priority
            };
            let Some((queued, bytes)) = lane.pop_front() else {
                return 0;
            };
            if queued.elapsed() > MAX_PACKET_AGE {
                self.stale.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            if buffer.len() < bytes.len() {
                lane.push_front((queued, bytes));
                return -2;
            }
            buffer[..bytes.len()].copy_from_slice(&bytes);
            return bytes.len() as i32;
        }
    }

    fn lanes(&self) -> std::sync::MutexGuard<'_, Lanes> {
        self.lanes.lock().unwrap_or_else(|error| error.into_inner())
    }
}

fn encode(source: u16, destination: u16, data: &[u8]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(7 + data.len());
    bytes.extend(b"MV1");
    bytes.extend(source.to_be_bytes());
    bytes.extend(destination.to_be_bytes());
    bytes.extend(data);
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `MV1` framing around an RTP header with a video payload type.
    fn video() -> Vec<u8> {
        encode(1, 2, &[0x80, 96, 0, 0])
    }

    #[test]
    fn a_video_backlog_still_admits_audio_and_control_first() {
        let outgoing = Outgoing::new();
        for _ in 0..VIDEO_CAPACITY {
            assert!(outgoing.offer(Instant::now(), video()));
        }
        assert!(
            !outgoing.offer(Instant::now(), video()),
            "the video lane is full"
        );
        let control = encode(1, 2, &[0; 20]);
        assert!(outgoing.offer(Instant::now(), control.clone()));
        let mut buffer = [0; MAX_PACKET];
        let length = outgoing.copy_packet(&mut buffer) as usize;
        assert_eq!(&buffer[..length], control.as_slice());
    }

    #[test]
    fn drops_before_moss_are_counted_by_cause() {
        let outgoing = Outgoing::new();
        for _ in 0..PRIORITY_CAPACITY {
            assert!(outgoing.offer(Instant::now(), vec![1; 7]));
        }
        assert!(
            !outgoing.offer(Instant::now(), vec![1; 7]),
            "the lane is full"
        );
        let mut buffer = [0; MAX_PACKET];
        while outgoing.copy_packet(&mut buffer) > 0 {}
        let aged = Instant::now() - MAX_PACKET_AGE - Duration::from_millis(1);
        assert!(outgoing.offer(aged, video()));
        assert_eq!(outgoing.copy_packet(&mut buffer), 0);
        assert_eq!(outgoing.dropped(), json!({"full": 1, "stale": 1}));
    }
}
