use super::{
    capture::Captured,
    diagnostics::Stalls,
    types::{Choices, Context, Frame, Signal, Snapshot, Surface},
};
use std::{collections::VecDeque, sync::Arc, time::Instant};

pub(crate) struct Presented {
    pub frame: Frame,
    pub received: Instant,
}

#[derive(Default)]
pub(crate) struct State {
    pub context: Option<Context>,
    pub prepared: bool,
    pub choices: Choices,
    /// Saved default awaiting the first camera start; explicit call picks win.
    pub pending_camera_default: Option<String>,
    pub snapshot: Snapshot,
    pub inbound: VecDeque<Signal>,
    pub outbound: VecDeque<(String, String, Signal)>,
    pub frames: [Option<Arc<Presented>>; 2],
    /// The window's local and remote video surfaces; they outlive calls.
    pub surfaces: [Surface; 2],
    pub sequences: [u64; 2],
    pub shutdown: bool,
    pub revision: u64,
    pub applied: u64,
    /// Owner stalls accumulated until the next statistics.
    pub stalls: Stalls,
}

impl State {
    pub fn reflect_choices(&mut self) {
        self.snapshot.microphone = self.choices.microphone
            && self.choices.microphone_allowed
            && !self.snapshot.inputs.is_empty();
        self.snapshot.microphone_requested = self.choices.microphone;
        self.snapshot.microphone_available = self.choices.microphone_allowed
            && self.snapshot.inputs.iter().any(|device| {
                self.choices
                    .input
                    .as_ref()
                    .is_none_or(|id| id == &device.id)
            });
        self.snapshot.input = self.choices.input.clone();
        self.snapshot.output = self.choices.output.clone();
        self.snapshot.camera_id = self.choices.camera_id.clone();
    }

    pub fn emit(&mut self, signal: Signal) {
        let Some(context) = &self.context else {
            return;
        };
        if self.outbound.len() >= 32 {
            self.outbound.pop_front();
        }
        self.outbound
            .push_back((context.session_id.clone(), context.call_id.clone(), signal));
    }

    /// Presents the capture at most at the local surface's size; the
    /// encoder takes the full frame separately. A scaler failure costs
    /// presentation bandwidth, never the preview, and is logged once.
    pub fn preview(&mut self, frame: &Captured) {
        static FAILED: std::sync::Once = std::sync::Once::new();
        let fitted =
            super::library::scale_rgba(frame.width, frame.height, &frame.pixels, self.surfaces[0])
                .unwrap_or_else(|error| {
                    FAILED.call_once(|| {
                        use crate::diagnostics_log::{kinds, write, LogLevel};
                        let message = format!("preview scaling failed; sending it whole: {error}");
                        write(LogLevel::Warn, kinds::CALL, "", &message);
                    });
                    None
                });
        let (width, height, pixels) =
            fitted.unwrap_or_else(|| (frame.width, frame.height, frame.pixels.clone()));
        self.present(
            width,
            height,
            pixels,
            frame.source_age_ms,
            frame.received,
            true,
        );
    }

    pub fn present(
        &mut self,
        width: u32,
        height: u32,
        pixels: Vec<u8>,
        age: u32,
        received: Instant,
        local: bool,
    ) {
        let Some(context) = &self.context else {
            return;
        };
        let lane = if local { 0 } else { 1 };
        self.sequences[lane] = self.sequences[lane].saturating_add(1);
        let sequence = self.sequences[lane];
        let frame = Frame {
            session_id: context.session_id.clone(),
            call_id: context.call_id.clone(),
            sequence,
            width,
            height,
            pixels,
            local,
            source_age_ms: age,
        };
        self.frames[lane] = Some(Arc::new(Presented { frame, received }));
    }
}
