//! The engine's packet thread: it carries one call's packets between the
//! engine and Moss in both directions, so a slow owner step neither ages
//! outgoing packets out nor holds inbound ones back.
use super::library::{error, CopyPacket, Receive, MAX_PACKET};
use std::{
    ffi::c_void,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

/// The Moss side of one call's packets, which the engine's packet thread
/// serves in both directions.
pub(crate) trait Wire: Send {
    /// Takes one outgoing packet and whether Moss sends it ahead of video.
    fn send(&mut self, packet: &[u8], priority: bool);
    /// Hands `deliver` every inbound packet that arrived since the last call.
    fn receive(&mut self, deliver: &mut dyn FnMut(&[u8]));
}

/// Well inside the engine's 200 ms packet age, finer than libwebrtc's 5 ms
/// pacing bursts, and short against its jitter buffer.
const PASS_INTERVAL: Duration = Duration::from_millis(2);

/// The engine's outgoing queue capacity. One pass sends at most this many
/// packets, so inbound packets and stop keep their turn while it refills.
const PASS_BUDGET: usize = 128;

/// The engine's packet ends, which the ABI lets any thread use.
pub(super) struct PacketEnds {
    pub handle: *mut c_void,
    pub receive: Receive,
    pub copy_packet: CopyPacket,
    pub priority: Receive,
}

// SAFETY: `receive`, `copy_packet` and `packet_priority` never touch the
// engine's owner state, and `Engine::drop` joins the packet thread before
// the handle goes.
unsafe impl Send for PacketEnds {}

impl PacketEnds {
    /// The engine refuses malformed or early packets itself.
    fn deliver(&self, packet: &[u8]) {
        // SAFETY: the engine outlives this thread; the packet is readable until return.
        unsafe { (self.receive)(self.handle, packet.as_ptr(), packet.len()) };
    }

    fn copy(&self, buffer: &mut [u8; MAX_PACKET]) -> Option<usize> {
        // SAFETY: the engine outlives this thread; the buffer is exclusively writable.
        let length = unsafe { (self.copy_packet)(self.handle, buffer.as_mut_ptr(), buffer.len()) };
        (length > 0 && length as usize <= buffer.len()).then_some(length as usize)
    }

    fn priority(&self, packet: &[u8]) -> bool {
        // SAFETY: the engine outlives this thread; the packet is readable until return.
        unsafe { (self.priority)(self.handle, packet.as_ptr(), packet.len()) == 1 }
    }
}

/// The thread that carries packets between the engine and its wire.
pub(super) struct Courier {
    stop: Arc<AtomicBool>,
    longest_gap_ms: Arc<AtomicU64>,
    thread: Option<JoinHandle<()>>,
}

impl Courier {
    pub fn start(packets: PacketEnds, mut wire: Box<dyn Wire>) -> Result<Self, String> {
        let stop = Arc::new(AtomicBool::new(false));
        let longest_gap_ms = Arc::new(AtomicU64::new(0));
        let (stopping, longest) = (stop.clone(), longest_gap_ms.clone());
        let thread = std::thread::Builder::new()
            .name("mosh-call-packets".into())
            .spawn(move || {
                let mut packet = [0; MAX_PACKET];
                let mut passed = Instant::now();
                while !stopping.load(Ordering::Acquire) {
                    let gap = u64::try_from(passed.elapsed().as_millis()).unwrap_or(u64::MAX);
                    longest.fetch_max(gap, Ordering::Relaxed);
                    passed = Instant::now();
                    wire.receive(&mut |inbound| packets.deliver(inbound));
                    for _ in 0..PASS_BUDGET {
                        let Some(length) = packets.copy(&mut packet) else {
                            break;
                        };
                        wire.send(&packet[..length], packets.priority(&packet[..length]));
                    }
                    std::thread::sleep(PASS_INTERVAL);
                }
            })
            .map_err(error)?;
        Ok(Self {
            stop,
            longest_gap_ms,
            thread: Some(thread),
        })
    }

    /// The longest pause between two passes since the previous call.
    pub fn take_longest_gap(&self) -> Duration {
        Duration::from_millis(self.longest_gap_ms.swap(0, Ordering::Relaxed))
    }

    /// Stops and joins the thread; call before the engine handle goes.
    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if self
            .thread
            .take()
            .is_some_and(|thread| thread.join().is_err())
        {
            crate::diagnostics_log::write(
                crate::diagnostics_log::LogLevel::Error,
                crate::diagnostics_log::kinds::CALL,
                "",
                "native media packet thread panicked; call packets stopped",
            );
        }
    }
}
