use super::{
    capture::{Capture, Prepared, Query},
    connection::Connection,
    packets::Sender,
    state::State,
    types::{Choices, Context, Signal, Surface},
};
use crate::private_dm_runtime::transport::DmTransport;
use serde_json::json;
use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

struct Owner {
    context: Option<Context>,
    connection: Option<Connection>,
    capture: Option<Capture>,
    query: Option<Query>,
    camera_inventory_ready: bool,
    choices: Choices,
    captured: u64,
    /// Bumped whenever capture starts or stops, so stale prepared frames drop.
    generation: u64,
    /// The local surface seen by the last step; previews are fitted to it.
    surface: Surface,
    capture_id: Option<String>,
    query_after: Instant,
    negotiation_since: Option<Instant>,
    sender: Sender,
}

/// Steps the call on a working copy of the state, so the shared lock is
/// held only to take what the app asked for and to publish the outcome. A
/// control from the app never waits out an engine or Moss call.
pub(super) fn run(shared: Arc<Mutex<State>>, transport: Arc<dyn DmTransport>) {
    let mut owner = Owner::new(transport.clone());
    let mut state = State::default();
    let lock = || shared.lock().unwrap_or_else(|error| error.into_inner());
    loop {
        let prepared = owner.prepare();
        let waiting = Instant::now();
        let Some(revision) = state.take(&mut lock()) else {
            return;
        };
        let lock_wait = super::diagnostics::Longest(waiting.elapsed());
        let stepping = Instant::now();
        if let Err(_error) = owner.step(&mut state, &*transport, prepared) {
            state.snapshot.failed = true;
        }
        state.stalls.step.since(stepping);
        state.stalls.lock_wait.include(lock_wait); // A new call's step resets stalls.
        state.publish(&mut lock(), revision);
        std::thread::sleep(Duration::from_millis(10));
    }
}

impl Owner {
    fn new(transport: Arc<dyn DmTransport>) -> Self {
        Self {
            context: None,
            connection: None,
            capture: None,
            query: None,
            camera_inventory_ready: false,
            choices: Choices::default(),
            captured: 0,
            generation: 0,
            surface: Surface::default(),
            capture_id: None,
            query_after: Instant::now(),
            negotiation_since: None,
            sender: Sender::new(transport),
        }
    }

    /// Fetches the latest capture frame and scales its preview outside the
    /// call state lock.
    fn prepare(&self) -> Option<Prepared> {
        let frame = self.capture.as_ref()?.frame(self.captured)?;
        Some(Prepared::new(self.generation, frame, self.surface))
    }

    fn step(
        &mut self,
        state: &mut State,
        transport: &dyn DmTransport,
        prepared: Option<Prepared>,
    ) -> Result<(), String> {
        self.surface = state.surfaces[0];
        self.synchronize(state);
        let Some(context) = state.context.clone() else {
            transport.drain_call_packets();
            return Ok(());
        };
        if !state.prepared {
            transport.drain_call_packets();
            return Ok(());
        }
        let capturing = Instant::now();
        self.query_cameras(state);
        let captured = self.capture(state, prepared);
        state.stalls.capture.since(capturing);
        captured?;
        self.negotiate(&context, state, Instant::now())?;
        let choices = state.choices.clone();
        if let Some(connection) = &mut self.connection {
            if self.choices != choices {
                apply_choices(connection, state)?;
                self.choices = state.choices.clone();
            }
            connection.pump(transport, &self.sender, state)?;
        }
        state.reflect_choices();
        state.expire(Instant::now());
        Ok(())
    }

    fn synchronize(&mut self, state: &mut State) {
        if state.context == self.context {
            return;
        }
        let merged = self
            .context
            .as_ref()
            .zip(state.context.as_ref())
            .is_some_and(|(old, new)| new.continues(old));
        if !merged {
            self.capture = None;
            self.connection = None;
            self.query = None;
            self.camera_inventory_ready = false;
            self.query_after = Instant::now();
            self.sender.reset();
            state.snapshot = Default::default();
            state.shown = Default::default();
            state.blank();
            state.outbound.clear();
            state.stalls = Default::default();
            self.captured = 0;
            self.negotiation_since = None;
        }
        if let Some(context) = &state.context {
            state.snapshot.session_id = context.session_id.clone();
            state.snapshot.call_id = context.call_id.clone();
        }
        self.context = state.context.clone();
    }

    fn capture(&mut self, state: &mut State, prepared: Option<Prepared>) -> Result<(), String> {
        let changed = self.capture.is_some() && self.capture_id != state.choices.camera_id;
        if (!state.choices.camera && (self.capture.is_some() || state.snapshot.camera_requested))
            || changed
        {
            self.stop_capture(state)?;
        }
        if state.choices.camera && self.capture.is_none() {
            state.snapshot.camera_failed = false;
            if !self.camera_ready(state) {
                state.snapshot.camera_requested = true;
                state.snapshot.camera_starting = true;
                return Ok(());
            }
            self.start_capture(state);
        }
        if self.capture.as_mut().is_some_and(Capture::failed) {
            state.choices.camera = false;
            state.snapshot.camera_failed = true;
            self.stop_capture(state)?;
        }
        if let Some(prepared) =
            prepared.filter(|p| self.capture.is_some() && p.generation == self.generation)
        {
            self.captured = prepared.frame.sequence;
            prepared.present(state, self.connection.as_ref().map(|c| &c.engine));
        }
        state.snapshot.camera_requested = state.choices.camera;
        state.snapshot.camera_starting = state.choices.camera && !state.snapshot.camera;
        Ok(())
    }

    fn query_cameras(&mut self, state: &mut State) {
        if self.query.is_none() && Instant::now() >= self.query_after {
            self.query_after = Instant::now() + Duration::from_secs(5);
            self.query = Query::start().ok();
            if self.query.is_none() {
                self.camera_inventory_ready = true;
            }
        }
        if let Some(devices) = self.query.as_mut().and_then(Query::poll) {
            match devices {
                Ok(devices) => state.snapshot.cameras = devices,
                Err(error) => warn(&format!(
                    "camera enumeration failed; keeping previous inventory: {error}"
                )),
            }
            self.camera_inventory_ready = true;
            self.query = None;
        }
    }

    fn camera_ready(&self, state: &mut State) -> bool {
        let Some(preferred) = state.pending_camera_default.as_ref() else {
            return true;
        };
        if state.choices.camera_id.as_ref() != Some(preferred) {
            state.pending_camera_default = None;
            return true;
        }
        if !self.camera_inventory_ready {
            return false;
        }
        state.choices.camera_id = state
            .snapshot
            .cameras
            .iter()
            .find(|device| device.stable && device.id == *preferred)
            .map(|device| device.id.clone());
        state.pending_camera_default = None;
        true
    }

    fn start_capture(&mut self, state: &mut State) {
        match Capture::start(state.choices.camera_id.as_deref()) {
            Ok(capture) => {
                self.generation += 1;
                self.capture_id = state.choices.camera_id.clone();
                self.capture = Some(capture);
            }
            Err(error) => {
                warn(&format!("camera capture startup failed: {error}"));
                state.choices.camera = false;
                state.snapshot.camera_failed = true;
            }
        }
    }

    fn stop_capture(&mut self, state: &mut State) -> Result<(), String> {
        let disabled = if let Some(connection) = &mut self.connection {
            let mut choices = state.choices.clone();
            choices.camera = false;
            connection.choices(&choices).map(|_| ())
        } else {
            Ok(())
        };
        // Reap the helper even when disabling a failed engine returns an error.
        self.capture = None;
        self.captured = 0;
        self.generation += 1;
        state.clear(true);
        state.snapshot.camera = false;
        disabled
    }

    fn negotiate(
        &mut self,
        context: &Context,
        state: &mut State,
        now: Instant,
    ) -> Result<(), String> {
        if !context.active {
            return Ok(());
        }
        let waiting = self.negotiation_since.get_or_insert(now);
        if self.connection.is_none()
            && now.saturating_duration_since(*waiting) >= Duration::from_secs(15)
        {
            state.snapshot.failed = true;
            return Ok(());
        }
        if self.connection.is_none() && context.caller {
            self.install(Connection::new(context.clone(), None, &self.sender)?, state)?;
        }
        for signal in state.inbound.drain(..).collect::<Vec<_>>() {
            if self.connection.is_none() {
                if let Signal::Description(offer) = signal {
                    self.install(
                        Connection::new(context.clone(), Some(offer), &self.sender)?,
                        state,
                    )?;
                }
                continue;
            }
            let connection = self.connection.as_mut().unwrap();
            if let Signal::Camera { nonce, enabled } = &signal {
                if nonce == &connection.binding.media_session {
                    state.snapshot.remote_camera = *enabled;
                    if !enabled {
                        state.clear(false);
                    }
                }
            }
            connection.apply(signal, state)?;
        }
        Ok(())
    }

    fn install(&mut self, mut connection: Connection, state: &mut State) -> Result<(), String> {
        let devices = connection.engine.ask(json!({"action":"devices"}))?;
        state.snapshot.inputs =
            serde_json::from_value(devices["inputs"].clone()).unwrap_or_default();
        state.snapshot.outputs =
            serde_json::from_value(devices["outputs"].clone()).unwrap_or_default();
        state.choices.input =
            super::devices::initial_pick(state.choices.input.as_deref(), &state.snapshot.inputs);
        state.choices.output =
            super::devices::initial_pick(state.choices.output.as_deref(), &state.snapshot.outputs);
        state.snapshot.microphone_available = !state.snapshot.inputs.is_empty();
        if !state.snapshot.microphone_available {
            state.choices.microphone = false;
        }
        apply_choices(&mut connection, state)?;
        self.choices = state.choices.clone();
        if !connection.context.caller {
            connection.start()?;
        }
        self.connection = Some(connection);
        Ok(())
    }
}

/// Applies the state's choices to the engine, timed as the `choices` stall.
/// A refused input turns the microphone off.
fn apply_choices(connection: &mut Connection, state: &mut State) -> Result<(), String> {
    let applying = Instant::now();
    let input_ok = connection.choices(&state.choices);
    state.stalls.choices.since(applying);
    if !input_ok? {
        state.choices.microphone = false;
    }
    Ok(())
}

fn warn(message: &str) {
    use crate::diagnostics_log::{kinds, write, LogLevel};
    write(LogLevel::Warn, kinds::CALL, "", message);
}

#[cfg(all(test, feature = "native-media-tests"))]
#[path = "reconnect_tests.rs"]
mod reconnect_tests;
#[cfg(test)]
#[path = "worker_tests.rs"]
mod tests;
