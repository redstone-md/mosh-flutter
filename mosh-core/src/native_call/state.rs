use super::{
    diagnostics::Stalls,
    texture::Texture,
    types::{Choices, Context, Frame, Signal, Snapshot, Surface},
};
use std::{collections::VecDeque, sync::Arc, time::Instant};

pub(crate) struct Presented {
    pub frame: Frame,
    pub received: Instant,
}

/// How long a lane keeps reporting its picture without a newer frame. A
/// shorter stall freezes the picture, as the app's renderer does for frames
/// it polls (`CallVideoFrame.lifetimeMs`).
const SHOWN_LIFETIME_MS: u128 = 5000;

/// When a lane last showed a frame, and how old its source was by then.
#[derive(Clone, Copy)]
pub(crate) struct Shown {
    pub received: Instant,
    pub source_age_ms: u32,
}

impl Shown {
    pub fn age_ms(&self, now: Instant) -> u128 {
        u128::from(self.source_age_ms) + now.saturating_duration_since(self.received).as_millis()
    }
}

/// The call signals kept for the owner; older ones go first.
pub(crate) const INBOUND_LIMIT: usize = 16;

/// The hub and the owner each hold one: the hub's is what the app asks for
/// and reads, the owner's is the working copy it steps.
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
    /// The latest frame of each lane the app polls: local, then remote.
    pub frames: [Option<Arc<Presented>>; 2],
    /// The main window's textures. A lane with one is written there and
    /// leaves no frame to poll. They outlive calls.
    pub textures: [Option<Texture>; 2],
    pub shown: [Option<Shown>; 2],
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
        self.choices = choices;
        self.show_request();
        self.revision = self.revision.saturating_add(1);
    }

    fn show_request(&mut self) {
        self.snapshot.microphone_requested = self.choices.microphone;
        self.snapshot.camera_requested = self.choices.camera;
        self.snapshot.input.clone_from(&self.choices.input);
        self.snapshot.output.clone_from(&self.choices.output);
        self.snapshot.camera_id.clone_from(&self.choices.camera_id);
    }

    /// Copies what the app asked for from `shared` into the owner's working
    /// copy, which the owner then steps without the lock. The revision it
    /// took, or `None` once the hub is gone.
    pub fn take(&mut self, shared: &mut State) -> Option<u64> {
        if shared.shutdown {
            return None;
        }
        let same = self
            .context
            .as_ref()
            .zip(shared.context.as_ref())
            .is_some_and(|(old, new)| new.continues(old));
        if !same {
            self.inbound.clear();
        }
        for signal in shared.inbound.drain(..) {
            if self.inbound.len() >= INBOUND_LIMIT {
                self.inbound.pop_front();
            }
            self.inbound.push_back(signal);
        }
        self.context.clone_from(&shared.context);
        self.prepared = shared.prepared;
        self.choices.clone_from(&shared.choices);
        self.pending_camera_default
            .clone_from(&shared.pending_camera_default);
        self.surfaces = shared.surfaces;
        self.textures = shared.textures;
        Some(shared.revision)
    }

    /// Publishes the step's outcome to `shared`. Choices the app made since
    /// the step took `revision` stay, in the state and in the snapshot; the
    /// next step applies them.
    pub fn publish(&mut self, shared: &mut State, revision: u64) {
        shared.snapshot.clone_from(&self.snapshot);
        if shared.revision == revision {
            shared.choices.clone_from(&self.choices);
            shared
                .pending_camera_default
                .clone_from(&self.pending_camera_default);
        } else {
            shared.show_request();
        }
        shared.frames.clone_from(&self.frames);
        for signal in self.outbound.drain(..) {
            shared.send(signal);
        }
        shared.applied = revision;
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
        let addressed = (context.session_id.clone(), context.call_id.clone(), signal);
        self.send(addressed);
    }

    fn send(&mut self, signal: (String, String, Signal)) {
        if self.outbound.len() >= 32 {
            self.outbound.pop_front();
        }
        self.outbound.push_back(signal);
    }

    /// Shows a lane's frame: in its texture, or else as the frame the app
    /// polls. The snapshot reports its size either way.
    pub fn present(
        &mut self,
        width: u32,
        height: u32,
        pixels: impl AsRef<[u8]> + Into<Vec<u8>>,
        age: u32,
        received: Instant,
        local: bool,
    ) {
        let Some(context) = &self.context else {
            return;
        };
        let lane = usize::from(!local);
        self.shown[lane] = Some(Shown {
            received,
            source_age_ms: age,
        });
        *self.snapshot.video(local) = Surface { width, height };
        if let Some(texture) = self.textures[lane] {
            texture.present(width, height, pixels.as_ref());
            self.frames[lane] = None;
            return;
        }
        self.sequences[lane] = self.sequences[lane].saturating_add(1);
        let sequence = self.sequences[lane];
        let frame = Frame {
            session_id: context.session_id.clone(),
            call_id: context.call_id.clone(),
            sequence,
            width,
            height,
            pixels: pixels.into(),
            local,
            source_age_ms: age,
        };
        self.frames[lane] = Some(Arc::new(Presented { frame, received }));
    }

    /// Stops showing a lane, whose texture keeps its last frame unseen.
    pub fn clear(&mut self, local: bool) {
        let lane = usize::from(!local);
        self.frames[lane] = None;
        self.shown[lane] = None;
        *self.snapshot.video(local) = Surface::default();
    }

    /// Reports no video for a lane whose picture has outlived its frame.
    pub fn expire(&mut self, now: Instant) {
        for local in [true, false] {
            let stale = self.shown[usize::from(!local)]
                .is_some_and(|shown| shown.age_ms(now) >= SHOWN_LIFETIME_MS);
            if stale {
                *self.snapshot.video(local) = Surface::default();
            }
        }
    }
}
