//! Camera adapters publish one latest, owned RGBA frame to the call owner.
use super::{
    library::{scale_rgba, Engine},
    state::State,
    types::Surface,
};
#[cfg(not(target_os = "android"))]
use std::time::{SystemTime, UNIX_EPOCH};
use std::{
    sync::{Arc, Once},
    time::Instant,
};

#[cfg(not(target_os = "android"))]
#[path = "capture/helper.rs"]
mod helper;
#[cfg(target_os = "android")]
#[path = "capture/android.rs"]
mod platform;
#[cfg(not(target_os = "android"))]
#[path = "capture/desktop.rs"]
mod platform;
pub(crate) use platform::{Capture, Query};

pub(crate) struct Captured {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub received: Instant,
    pub source_age_ms: u32,
}

/// A capture frame with its preview already fitted to the local surface, so
/// the owner scales it before taking the call state lock.
pub(crate) struct Prepared {
    /// The owner's capture generation the frame came from.
    pub generation: u64,
    pub frame: Arc<Captured>,
    preview: (u32, u32, Vec<u8>),
}

impl Prepared {
    /// A scaler failure costs presentation bandwidth, never the preview, and
    /// is logged once.
    pub fn new(generation: u64, frame: Arc<Captured>, surface: Surface) -> Self {
        static FAILED: Once = Once::new();
        let fitted =
            scale_rgba(frame.width, frame.height, &frame.pixels, surface).unwrap_or_else(|error| {
                FAILED.call_once(|| {
                    use crate::diagnostics_log::{kinds, write, LogLevel};
                    let message = format!("preview scaling failed; sending it whole: {error}");
                    write(LogLevel::Warn, kinds::CALL, "", &message);
                });
                None
            });
        let preview = fitted.unwrap_or_else(|| (frame.width, frame.height, frame.pixels.clone()));
        Self {
            generation,
            frame,
            preview,
        }
    }

    /// The encoder takes the whole capture and the window its preview, both
    /// only while the frame is under a second old.
    pub fn present(self, state: &mut State, engine: Option<&Engine>) {
        let frame = &self.frame;
        if u128::from(frame.source_age_ms) + frame.received.elapsed().as_millis() >= 1000 {
            return;
        }
        if let Some(engine) = engine {
            engine.push(frame.width, frame.height, &frame.pixels);
        }
        let (width, height, pixels) = self.preview;
        state.present(
            width,
            height,
            pixels,
            frame.source_age_ms,
            frame.received,
            true,
        );
        state.snapshot.camera = true;
    }
}

#[cfg(not(target_os = "android"))]
pub(crate) fn wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_call::types::Context;
    use std::time::Duration;

    fn aged(received_ms: u64, source_age_ms: u32) -> Prepared {
        let frame = Captured {
            sequence: 1,
            width: 1,
            height: 1,
            pixels: vec![0; 4],
            received: Instant::now() - Duration::from_millis(received_ms),
            source_age_ms,
        };
        Prepared::new(0, Arc::new(frame), Surface::default())
    }

    #[test]
    fn delayed_capture_is_not_admitted_as_live_camera_video() {
        let mut state = State {
            context: Some(Context {
                session_id: "dm".into(),
                call_id: "call".into(),
                superseded: None,
                active: false,
                caller: true,
                caller_signer: "caller".into(),
                callee_signer: None,
                peer: String::new(),
            }),
            ..Default::default()
        };
        aged(1100, 0).present(&mut state, None);
        assert!(!state.snapshot.camera);
        assert!(state.frames[0].is_none());
        aged(600, 500).present(&mut state, None);
        assert!(state.frames[0].is_none());
        aged(0, 0).present(&mut state, None);
        assert!(state.snapshot.camera);
        assert!(state.frames[0].is_some());
    }
}
