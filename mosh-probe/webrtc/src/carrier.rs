//! The engine's side of Moss: the virtual network, `MV1` framing (source
//! port, destination port, UDP payload) and the bounded outgoing queue the
//! owner drains with `copy_packet`.
use std::net::{Ipv4Addr, SocketAddrV4};
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
    mpsc::{Receiver, sync_channel},
};
use std::time::{Duration, Instant};

use libwebrtc::virtual_network::VirtualNetwork;

pub const MAX_PACKET: usize = 2007;
const MAX_PACKET_AGE: Duration = Duration::from_millis(200);
const CALLER_IP: Ipv4Addr = Ipv4Addr::new(192, 0, 2, 1);
const CALLEE_IP: Ipv4Addr = Ipv4Addr::new(192, 0, 2, 2);

pub struct Carrier {
    network: VirtualNetwork,
    peer: Ipv4Addr,
    packets: Receiver<(Instant, Vec<u8>)>,
    pending: Option<(Instant, Vec<u8>)>,
    dropped: Arc<AtomicU64>,
    audio_payloads: [bool; 128],
}

impl Carrier {
    pub fn new(caller: bool) -> Self {
        let (send, packets) = sync_channel(128);
        let dropped = Arc::new(AtomicU64::new(0));
        let measured = dropped.clone();
        let (ip, peer) = if caller {
            (CALLER_IP, CALLEE_IP)
        } else {
            (CALLEE_IP, CALLER_IP)
        };
        let network = VirtualNetwork::new(ip, move |port, to, data| {
            let bytes = encode(port, to.port(), data);
            let sent = bytes.len() <= MAX_PACKET && send.try_send((Instant::now(), bytes)).is_ok();
            if !sent {
                measured.fetch_add(1, Ordering::Relaxed);
            }
            sent
        });
        Self {
            network,
            peer,
            packets,
            pending: None,
            dropped,
            audio_payloads: [false; 128],
        }
    }

    pub fn network(&self) -> &VirtualNetwork {
        &self.network
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    /// Remembers the audio payload types of the local SDP for `priority`.
    pub fn learn(&mut self, sdp: &str) {
        let payloads = sdp
            .lines()
            .filter(|line| line.starts_with("m=audio "))
            .flat_map(|line| line.split_ascii_whitespace().skip(3))
            .filter_map(|payload| payload.parse::<usize>().ok());
        for payload in payloads {
            if let Some(audio) = self.audio_payloads.get_mut(payload) {
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
        self.audio_payloads[usize::from(data[1] & 127)]
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

    /// Copies the next fresh packet; -2 when `buffer` is too small for it.
    pub fn copy_packet(&mut self, buffer: &mut [u8]) -> i32 {
        loop {
            let Some((queued, bytes)) =
                self.pending.take().or_else(|| self.packets.try_recv().ok())
            else {
                return 0;
            };
            if queued.elapsed() > MAX_PACKET_AGE {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            if buffer.len() < bytes.len() {
                self.pending = Some((queued, bytes));
                return -2;
            }
            buffer[..bytes.len()].copy_from_slice(&bytes);
            return bytes.len() as i32;
        }
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
