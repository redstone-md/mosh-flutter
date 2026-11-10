use super::{
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
    /// Takes the user's choices for the owner's next step. The snapshot shows
    /// what was asked at once, so a reader never sees an older request; what
    /// the devices do follows once the owner applies them.
    pub fn request(&mut self, choices: Choices) {
        self.snapshot.microphone_requested = choices.microphone;
        self.snapshot.camera_requested = choices.camera;
        self.snapshot.input.clone_from(&choices.input);
        self.snapshot.output.clone_from(&choices.output);
        self.snapshot.camera_id.clone_from(&choices.camera_id);
        self.choices = choices;
        self.revision = self.revision.saturating_add(1);
    }

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
