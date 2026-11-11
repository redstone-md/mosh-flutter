//! A video texture of the main window. Its platform plugin owns the Flutter
//! texture and the pixels it shows; Rust hands it each frame, so pixels never
//! pass through flutter_rust_bridge or Dart.
use std::ptr::NonNull;

/// What the plugin exports for one texture, for as long as the process
/// lives. `linux/runner/call_video_texture.h` declares the same layout.
#[repr(C)]
pub(crate) struct Exported {
    /// Copies a `width` by `height` RGBA frame and schedules its display. A
    /// frame not shown yet is replaced. Any thread may call it.
    pub present: unsafe extern "C" fn(*const Exported, *const u8, u32, u32),
}

#[derive(Clone, Copy)]
pub(crate) struct Texture(NonNull<Exported>);

// SAFETY: the plugin keeps the export for the process's life and lets any
// thread call `present`.
unsafe impl Send for Texture {}

impl Texture {
    /// The texture exported at `address`, or none for zero.
    ///
    /// # Safety
    /// A non-zero `address` is an [`Exported`] the plugin never frees.
    pub unsafe fn at(address: i64) -> Option<Self> {
        NonNull::new(address as usize as *mut Exported).map(Self)
    }

    pub fn present(self, width: u32, height: u32, pixels: &[u8]) {
        if pixels.len() != width as usize * height as usize * 4 {
            return;
        }
        // SAFETY: `at`'s caller vouched for the export; the pixels are
        // readable until the call returns.
        unsafe { (self.0.as_ref().present)(self.0.as_ptr(), pixels.as_ptr(), width, height) }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::native_call::{
        state::State,
        types::{Context, Surface},
        Hub,
    };
    use std::{
        sync::{Arc, Mutex},
        time::{Duration, Instant},
    };

    /// A plugin's texture that keeps every frame it was handed.
    #[repr(C)]
    pub(crate) struct Recording {
        exported: Exported,
        frames: Mutex<Vec<(u32, u32, Vec<u8>)>>,
    }

    impl Recording {
        /// Leaked, as a plugin's export lives for the process.
        pub fn start() -> &'static Self {
            Box::leak(Box::new(Self {
                exported: Exported { present: record },
                frames: Mutex::default(),
            }))
        }

        pub fn texture(&'static self) -> Texture {
            Texture(NonNull::from(&self.exported))
        }

        pub fn frames(&self) -> Vec<(u32, u32, Vec<u8>)> {
            self.frames.lock().unwrap().clone()
        }
    }

    unsafe extern "C" fn record(exported: *const Exported, pixels: *const u8, w: u32, h: u32) {
        // SAFETY: `exported` is the first field of a leaked `Recording`.
        let recording = unsafe { &*exported.cast::<Recording>() };
        // SAFETY: the caller hands over `w * h * 4` readable bytes.
        let pixels = unsafe { std::slice::from_raw_parts(pixels, (w * h * 4) as usize) };
        recording
            .frames
            .lock()
            .unwrap()
            .push((w, h, pixels.to_vec()));
    }

    fn call() -> State {
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

    #[test]
    fn a_lane_shown_in_a_texture_hands_the_app_its_size_and_no_pixels() {
        let shared = Arc::new(Mutex::new(call()));
        let hub = Hub {
            state: shared.clone(),
        };
        // A step before the textures arrive leaves a frame to poll.
        let mut owner = State::default();
        let revision = owner.take(&mut shared.lock().unwrap()).unwrap();
        owner.present(1, 1, vec![7; 4], 0, Instant::now(), true);
        owner.publish(&mut shared.lock().unwrap(), revision);
        assert!(hub.frame("dm", "call", true, 0).is_some());

        let preview = Recording::start();
        hub.show_in(Some(preview.texture()), None).unwrap();
        let revision = owner.take(&mut shared.lock().unwrap()).unwrap();
        let pixels = vec![1, 2, 3, 4, 5, 6, 7, 8];
        owner.present(2, 1, pixels.clone(), 0, Instant::now(), true);
        owner.present(1, 1, vec![9; 4], 0, Instant::now(), false);
        owner.publish(&mut shared.lock().unwrap(), revision);

        assert_eq!(preview.frames(), [(2, 1, pixels)]);
        assert!(hub.frame("dm", "call", true, 0).is_none());
        let remote = hub.frame("dm", "call", false, 0).unwrap();
        assert_eq!(remote.pixels, [9; 4], "a lane without a texture is polled");
        let snapshot = hub.snapshot("dm", "call").unwrap();
        let size = |width, height| Surface { width, height };
        assert_eq!(snapshot.local_video, size(2, 1));
        assert_eq!(snapshot.remote_video, size(1, 1));
    }

    #[test]
    fn a_picture_frozen_for_five_seconds_is_reported_gone_until_its_next_frame() {
        let mut state = call();
        let now = Instant::now();
        let shown = now - Duration::from_millis(4700);
        state.present(1, 1, vec![0; 4], 200, shown, false);
        state.expire(now);
        assert_eq!(state.snapshot.remote_video.width, 1, "a stall freezes it");
        state.expire(now + Duration::from_millis(100));
        assert_eq!(state.snapshot.remote_video, Surface::default());
        state.present(1, 1, vec![0; 4], 0, now, false);
        state.expire(now);
        assert_eq!(state.snapshot.remote_video.width, 1);
    }

    #[test]
    fn a_stopped_lane_reports_no_video() {
        let mut state = call();
        state.present(1, 1, vec![0; 4], 0, Instant::now(), true);
        state.clear(true);
        assert_eq!(state.snapshot.local_video, Surface::default());
        assert!(state.frames[0].is_none());
    }
}
