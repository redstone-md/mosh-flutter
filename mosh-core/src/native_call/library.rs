//! Load and use the isolated graph on its owning thread. Only its packets
//! cross to another thread, which the engine joins on drop.
use super::types::Binding;
use libloading::Library;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_void, CStr, CString},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, OnceLock,
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

pub const MAX_RGBA: usize = 1920 * 1080 * 4;
pub const MAX_PACKET: usize = 2007;
type Create = unsafe extern "C" fn(*const c_char) -> *mut c_void;
type Command = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_char);
type DropEngine = unsafe extern "C" fn(*mut c_void);
type Receive = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32;
type CopyPacket = unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> i32;
type Push = unsafe extern "C" fn(*mut c_void, u32, u32, *const u8, usize) -> i32;
type CopyFrame = unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize, *mut FrameInfo) -> i32;

#[repr(C)]
#[derive(Default)]
pub(crate) struct FrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: u32,
    pub age_ms: u32,
}

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

pub(crate) struct Engine {
    handle: *mut c_void,
    command: Command,
    free: Free,
    drop_engine: DropEngine,
    push: Push,
    copy_frame: CopyFrame,
    courier: Courier,
    _library: &'static Library,
}

impl Engine {
    /// Starts the engine and carries its packets over `wire` from a thread
    /// of its own, so a slow owner step neither ages outgoing packets out
    /// nor holds inbound ones back.
    pub fn new(binding: &Binding, caller: bool, wire: Box<dyn Wire>) -> Result<Self, String> {
        let config =
            CString::new(json!({"binding":binding,"caller":caller}).to_string()).map_err(error)?;
        let library = media_library()?;
        // SAFETY: these signatures match the pinned Mosh ABI. Retain the library through drop.
        let (create, command, free, drop_engine, receive, priority, copy_packet, push, copy_frame) = unsafe {
            (
                symbol::<Create>(library, b"mosh_media_create\0")?,
                symbol::<Command>(library, b"mosh_media_command\0")?,
                symbol::<Free>(library, b"mosh_media_free\0")?,
                symbol::<DropEngine>(library, b"mosh_media_drop\0")?,
                symbol::<Receive>(library, b"mosh_media_receive\0")?,
                symbol::<Receive>(library, b"mosh_media_packet_priority\0")?,
                symbol::<CopyPacket>(library, b"mosh_media_copy_packet\0")?,
                symbol::<Push>(library, b"mosh_media_push_rgba\0")?,
                symbol::<CopyFrame>(library, b"mosh_media_copy_frame\0")?,
            )
        };
        // SAFETY: config is retained until this synchronous create returns.
        let handle = unsafe { create(config.as_ptr()) };
        if handle.is_null() {
            return Err("native media creation failed".into());
        }
        let packets = Packets {
            handle,
            receive,
            copy_packet,
            priority,
        };
        let courier = match Courier::start(packets, wire) {
            Ok(courier) => courier,
            Err(failure) => {
                // SAFETY: no thread uses the handle yet; return it once.
                unsafe { drop_engine(handle) };
                return Err(failure);
            }
        };
        Ok(Self {
            handle,
            command,
            free,
            drop_engine,
            push,
            copy_frame,
            courier,
            _library: library,
        })
    }

    /// The longest pause between two passes of the packet thread since the
    /// previous call.
    pub fn take_longest_drain_gap(&self) -> Duration {
        Duration::from_millis(self.courier.longest_gap_ms.swap(0, Ordering::Relaxed))
    }

    pub fn ask(&mut self, value: Value) -> Result<Value, String> {
        #[cfg(target_os = "android")]
        if matches!(value["action"].as_str(), Some("devices" | "select")) {
            return crate::android::media::command(value);
        }
        let command = CString::new(value.to_string()).map_err(error)?;
        // SAFETY: this owner retains the handle, library and command throughout the call.
        let result = unsafe { (self.command)(self.handle, command.as_ptr()) };
        if result.is_null() {
            return Err("native media returned no result".into());
        }
        // SAFETY: ABI result is a NUL-terminated allocation retained until free below.
        let value = serde_json::from_slice::<Value>(unsafe { CStr::from_ptr(result) }.to_bytes());
        // SAFETY: return the allocation to its library once, including when parsing fails.
        unsafe { (self.free)(result) };
        let value = value.map_err(error)?;
        if let Some(error) = value["error"].as_str() {
            return Err(error.into());
        }
        Ok(value)
    }

    pub fn push(&self, width: u32, height: u32, pixels: &[u8]) -> bool {
        // SAFETY: retain handle/library and a readable RGBA buffer until return.
        unsafe { (self.push)(self.handle, width, height, pixels.as_ptr(), pixels.len()) == 1 }
    }

    pub fn frame(&self, after: u64, pixels: &mut [u8]) -> Option<FrameInfo> {
        let mut info = FrameInfo::default();
        // SAFETY: retain handle/library and disjoint exclusively writable output allocations.
        let status = unsafe {
            (self.copy_frame)(
                self.handle,
                after,
                pixels.as_mut_ptr(),
                pixels.len(),
                &mut info,
            )
        };
        if status != 1
            || info.width == 0
            || info.height == 0
            || info.width > 1920
            || info.height > 1920
            || info.rgba_bytes as usize > pixels.len()
            || info.rgba_bytes as usize > MAX_RGBA
            || info.width as u64 * info.height as u64 * 4 != u64::from(info.rgba_bytes)
        {
            return None;
        }
        Some(info)
    }
}

/// Media protocol of the engine before libwebrtc and of clients that predate
/// the field; a peer on it ends the call with `update_required`.
pub(crate) const LEGACY_MEDIA_PROTOCOL: u32 = 1;

/// What a build whose engine cannot load speaks. It is not the legacy value,
/// so an older client's offer does not ring a call neither side can carry.
const NO_ENGINE_MEDIA_PROTOCOL: u32 = 0;

/// The packaged engine's media protocol, carried in every call control.
pub(crate) fn media_protocol() -> u32 {
    type Protocol = unsafe extern "C" fn() -> u32;
    static PROTOCOL: OnceLock<u32> = OnceLock::new();
    *PROTOCOL.get_or_init(|| {
        // SAFETY: the pinned ABI declares this symbol with exactly this signature;
        // the library stays mapped until process exit.
        let protocol = media_library().and_then(|library| unsafe {
            library
                .get::<Protocol>(b"mosh_media_protocol\0")
                .map(|protocol| protocol())
                .map_err(error)
        });
        protocol.unwrap_or_else(|failure| {
            crate::diagnostics_log::write(
                crate::diagnostics_log::LogLevel::Error,
                crate::diagnostics_log::kinds::CALL,
                "media-protocol",
                &format!("native media engine unavailable: {failure}"),
            );
            NO_ENGINE_MEDIA_PROTOCOL
        })
    })
}

fn media_library() -> Result<&'static Library, String> {
    // Native dependencies have process-global state and thread-local cleanup.
    // Destroy each engine, but keep its executable code mapped until process exit.
    static LIBRARY: OnceLock<Result<Library, String>> = OnceLock::new();
    LIBRARY
        .get_or_init(|| {
            let path = artifact("MOSH_MEDIA_ENGINE", library_name())?;
            // SAFETY: load only the packaged or explicitly selected local artifact.
            unsafe { Library::new(path) }.map_err(error)
        })
        .as_ref()
        .map_err(Clone::clone)
}

/// The engine's packet ends, which the ABI lets any thread use.
struct Packets {
    handle: *mut c_void,
    receive: Receive,
    copy_packet: CopyPacket,
    priority: Receive,
}

// SAFETY: `receive`, `copy_packet` and `packet_priority` never touch the
// engine's owner state, and `Engine::drop` joins the packet thread before
// the handle goes.
unsafe impl Send for Packets {}

impl Packets {
    fn deliver(&self, packet: &[u8]) {
        if (7..=MAX_PACKET).contains(&packet.len()) {
            // SAFETY: the engine outlives this thread; the packet is readable until return.
            unsafe { (self.receive)(self.handle, packet.as_ptr(), packet.len()) };
        }
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
struct Courier {
    stop: Arc<AtomicBool>,
    longest_gap_ms: Arc<AtomicU64>,
    thread: Option<JoinHandle<()>>,
}

impl Courier {
    fn start(packets: Packets, mut wire: Box<dyn Wire>) -> Result<Self, String> {
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
                    while let Some(length) = packets.copy(&mut packet) {
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

    fn stop(&mut self) {
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

impl Drop for Engine {
    fn drop(&mut self) {
        // The packet thread borrows the handle, so it stops before the handle goes;
        // fields drop only after this body, too late for that.
        self.courier.stop();
        // SAFETY: owner returns the unique handle before unloading its library.
        unsafe { (self.drop_engine)(self.handle) };
        #[cfg(target_os = "android")]
        let _ = crate::android::media::command(json!({"action":"audioStop"}));
    }
}

fn library_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "mosh_native_media.dll"
    } else if cfg!(target_os = "macos") {
        "libmosh_native_media.dylib"
    } else {
        "libmosh_native_media.so"
    }
}

pub(crate) fn artifact(variable: &str, name: &str) -> Result<PathBuf, String> {
    if cfg!(target_os = "android") {
        // Android's linker resolves only libraries in the APK's native namespace.
        return Ok(PathBuf::from(name));
    }
    if let Some(path) = std::env::var_os(variable) {
        return Ok(PathBuf::from(path));
    }
    let executable = std::env::current_exe().map_err(error)?;
    let directory = executable.parent().ok_or("missing executable directory")?;
    for path in [
        directory.join(name),
        directory.join("lib").join(name),
        directory.join("../Frameworks").join(name),
        directory.join("../Helpers").join(name),
    ] {
        if path.is_file() {
            return Ok(path);
        }
    }
    Err(format!("packaged native artifact is missing: {name}"))
}

#[cfg(target_os = "android")]
pub(crate) fn i420_size(width: u32, height: u32) -> Option<usize> {
    (width > 0
        && height > 0
        && width <= 1920
        && height <= 1920
        && width.is_multiple_of(2)
        && height.is_multiple_of(2)
        && u64::from(width) * u64::from(height) * 4 <= MAX_RGBA as u64)
        .then(|| width as usize * height as usize * 3 / 2)
}

#[cfg(target_os = "android")]
pub(crate) fn i420_to_rgba(width: u32, height: u32, planar: &[u8]) -> Result<Vec<u8>, String> {
    type Convert = unsafe extern "C" fn(u32, u32, *const u8, usize, *mut u8, usize) -> i32;
    if i420_size(width, height) != Some(planar.len()) {
        return Err("invalid I420 frame".into());
    }
    let library = media_library()?;
    let mut rgba = vec![0; width as usize * height as usize * 4];
    // SAFETY: the pinned converter retains no pointers. Both sized buffers and
    // its executable library remain alive until conversion returns.
    let success = unsafe {
        let convert = library
            .get::<Convert>(b"mosh_media_i420_to_rgba\0")
            .map_err(error)?;
        convert(
            width,
            height,
            planar.as_ptr(),
            planar.len(),
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    if success == 1 {
        Ok(rgba)
    } else {
        Err("I420 conversion failed".into())
    }
}

/// # Safety
/// `T` is the symbol's pinned ABI signature.
unsafe fn symbol<T: Copy>(library: &Library, name: &[u8]) -> Result<T, String> {
    // SAFETY: the caller pins `T` to the symbol's signature.
    unsafe { library.get::<T>(name) }
        .map(|symbol| *symbol)
        .map_err(error)
}

fn error(error: impl std::fmt::Display) -> String {
    error.to_string()
}
