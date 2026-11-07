//! The engine's side of Moss: the virtual network, `MV1` framing (source
//! port, destination port, UDP payload) and the bounded outgoing queue the
//! owner drains with `copy_packet`.
use std::net::{Ipv4Addr, SocketAddrV4};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
    mpsc::{Receiver, SyncSender, sync_channel},
};
use std::time::{Duration, Instant};

use libwebrtc::virtual_network::VirtualNetwork;
use serde_json::{Value, json};

pub const MAX_PACKET: usize = 2007;
const MAX_PACKET_AGE: Duration = Duration::from_millis(200);
const QUEUE: usize = 128;
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

    /// The queue the owner drains; it never waits for the engine.
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

/// Outgoing packets between libwebrtc's network thread and the owner.
pub struct Outgoing {
    send: SyncSender<(Instant, Vec<u8>)>,
    lane: Mutex<Lane>,
    full: AtomicU64,
    stale: AtomicU64,
}

struct Lane {
    packets: Receiver<(Instant, Vec<u8>)>,
    pending: Option<(Instant, Vec<u8>)>,
    audio_payloads: [bool; 128],
}

impl Outgoing {
    fn new() -> Self {
        let (send, packets) = sync_channel(QUEUE);
        Self {
            send,
            lane: Mutex::new(Lane {
                packets,
                pending: None,
                audio_payloads: [false; 128],
            }),
            full: AtomicU64::new(0),
            stale: AtomicU64::new(0),
        }
    }

    /// Queues one framed packet; false when it is oversized or the queue is full.
    fn offer(&self, queued: Instant, bytes: Vec<u8>) -> bool {
        let sent = bytes.len() <= MAX_PACKET && self.send.try_send((queued, bytes)).is_ok();
        if !sent {
            self.full.fetch_add(1, Ordering::Relaxed);
        }
        sent
    }

    /// Packets dropped before Moss: refused by a full queue, or older than
    /// the packet age when the owner came for them.
    pub fn dropped(&self) -> Value {
        json!({
            "full": self.full.load(Ordering::Relaxed),
            "stale": self.stale.load(Ordering::Relaxed),
        })
    }

    /// Remembers the audio payload types of the local SDP for `priority`.
    pub fn learn(&self, sdp: &str) {
        let mut lane = self.lane();
        let payloads = sdp
            .lines()
            .filter(|line| line.starts_with("m=audio "))
            .flat_map(|line| line.split_ascii_whitespace().skip(3))
            .filter_map(|payload| payload.parse::<usize>().ok());
        for payload in payloads {
            if let Some(audio) = lane.audio_payloads.get_mut(payload) {
                *audio = true;
            }
        }
    }

    /// True for audio RTP and for everything that is not RTP media (ICE,
    /// DTLS, RTCP), which Moss sends ahead of video.
    pub fn priority(&self, packet: &[u8]) -> bool {
        let Some(data) = packet.get(7..) else {
            return true;
        };
        if data.len() < 2 || data[0] >> 6 != 2 || (192..=223).contains(&data[1]) {
            return true;
        }
        self.lane().audio_payloads[usize::from(data[1] & 127)]
    }

    /// Copies the next fresh packet; -2 when `buffer` is too small for it.
    pub fn copy_packet(&self, buffer: &mut [u8]) -> i32 {
        let mut lane = self.lane();
        loop {
            let Some((queued, bytes)) =
                lane.pending.take().or_else(|| lane.packets.try_recv().ok())
            else {
                return 0;
            };
            if queued.elapsed() > MAX_PACKET_AGE {
                self.stale.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            if buffer.len() < bytes.len() {
                lane.pending = Some((queued, bytes));
                return -2;
            }
            buffer[..bytes.len()].copy_from_slice(&bytes);
            return bytes.len() as i32;
        }
    }

    fn lane(&self) -> std::sync::MutexGuard<'_, Lane> {
        self.lane.lock().unwrap_or_else(|error| error.into_inner())
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

    #[test]
    fn drops_before_moss_are_counted_by_cause() {
        let outgoing = Outgoing::new();
        for _ in 0..QUEUE {
            assert!(outgoing.offer(Instant::now(), vec![1; 7]));
        }
        assert!(
            !outgoing.offer(Instant::now(), vec![1; 7]),
            "the queue is full"
        );
        let mut buffer = [0; MAX_PACKET];
        while outgoing.copy_packet(&mut buffer) > 0 {}
        let aged = Instant::now() - MAX_PACKET_AGE - Duration::from_millis(1);
        assert!(outgoing.offer(aged, vec![2; 7]));
        assert_eq!(outgoing.copy_packet(&mut buffer), 0);
        assert_eq!(outgoing.dropped(), json!({"full": 1, "stale": 1}));
    }
}
