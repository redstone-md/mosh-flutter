use super::{
    capture::{Capture, Query},
    connection::Connection,
    packets::Sender,
    state::State,
    types::{Choices, Context, Signal},
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
    choices: Choices,
    captured: u64,
    capture_id: Option<String>,
    query_after: Instant,
    negotiation_since: Option<Instant>,
    sender: Sender,
}

pub(super) fn run(shared: Arc<Mutex<State>>, transport: Arc<dyn DmTransport>) {
    let mut owner = Owner {
        context: None,
        connection: None,
        capture: None,
        query: None,
        choices: Choices::default(),
        captured: 0,
        capture_id: None,
        query_after: Instant::now(),
        negotiation_since: None,
        sender: Sender::new(transport.clone()),
    };
    loop {
        let started = Instant::now();
        let mut state = shared.lock().unwrap_or_else(|error| error.into_inner());
        if state.shutdown {
            return;
        }
        if let Err(error) = owner.step(&mut state, &*transport) {
            super::diagnose(format_args!("worker failed: {error}"));
            state.snapshot.failed = true;
        }
        if started.elapsed() >= Duration::from_millis(500) {
            super::diagnose(format_args!(
                "worker iteration took {:?}",
                started.elapsed()
            ));
        }
        state.applied = state.revision;
        drop(state);
        std::thread::sleep(Duration::from_millis(10));
    }
}

impl Owner {
    fn step(&mut self, state: &mut State, transport: &dyn DmTransport) -> Result<(), String> {
        self.synchronize(state);
        let Some(context) = state.context.clone() else {
            transport.drain_call_packets();
            return Ok(());
        };
        if !state.prepared {
            transport.drain_call_packets();
            return Ok(());
        }
        self.capture(state)?;
        if self.query.is_none() && Instant::now() >= self.query_after {
            self.query_after = Instant::now() + Duration::from_secs(5);
            self.query = Query::start().ok();
        }
        if let Some(devices) = self.query.as_mut().and_then(Query::poll) {
            state.snapshot.cameras = devices;
            self.query = None;
        }
        self.negotiate(&context, state)?;
        let choices = state.choices.clone();
        if let Some(connection) = &mut self.connection {
            if self.choices != choices {
                if !connection.choices(&choices)? {
                    state.choices.microphone = false;
                }
                self.choices = state.choices.clone();
            }
            connection.pump(transport, &self.sender, state)?;
        }
        state.reflect_choices();
        Ok(())
    }

    fn synchronize(&mut self, state: &mut State) {
        if state.context == self.context {
            return;
        }
        super::diagnose(format_args!(
            "context changed: caller={:?} active={:?} prepared={}",
            state.context.as_ref().map(|context| context.caller),
            state.context.as_ref().map(|context| context.active),
            state.prepared
        ));
        let merged = self
            .context
            .as_ref()
            .zip(state.context.as_ref())
            .is_some_and(|(old, new)| {
                old.session_id == new.session_id
                    && (old.call_id == new.call_id || new.superseded.as_ref() == Some(&old.call_id))
            });
        if !merged {
            self.capture = None;
            self.connection = None;
            self.query = None;
            self.sender.reset();
            state.snapshot = Default::default();
            state.frames = Default::default();
            state.sequences = [0; 2];
            state.outbound.clear();
            self.captured = 0;
            self.negotiation_since = None;
        }
        if let Some(context) = &state.context {
            state.snapshot.session_id = context.session_id.clone();
            state.snapshot.call_id = context.call_id.clone();
        }
        self.context = state.context.clone();
    }

    fn capture(&mut self, state: &mut State) -> Result<(), String> {
        let changed = self.capture.is_some() && self.capture_id != state.choices.camera_id;
        if (!state.choices.camera && (self.capture.is_some() || state.snapshot.camera_requested))
            || changed
        {
            self.stop_capture(state)?;
        }
        if state.choices.camera && self.capture.is_none() {
            state.snapshot.camera_failed = false;
            match Capture::start(state.choices.camera_id.as_deref()) {
                Ok(capture) => {
                    self.capture_id = state.choices.camera_id.clone();
                    self.capture = Some(capture);
                }
                Err(_) => {
                    state.choices.camera = false;
                    state.snapshot.camera_failed = true;
                }
            }
        }
        if self.capture.as_mut().is_some_and(Capture::failed) {
            super::diagnose(format_args!("camera helper stalled or exited"));
            state.choices.camera = false;
            state.snapshot.camera_failed = true;
            self.stop_capture(state)?;
        }
        if let Some(frame) = self
            .capture
            .as_ref()
            .and_then(|capture| capture.frame(self.captured))
        {
            self.captured = frame.sequence;
            present_capture(&frame, state, self.connection.as_ref());
        }
        state.snapshot.camera_requested = state.choices.camera;
        state.snapshot.camera_starting = state.choices.camera && !state.snapshot.camera;
        Ok(())
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
        state.frames[0] = None;
        state.snapshot.camera = false;
        disabled
    }

    fn negotiate(&mut self, context: &Context, state: &mut State) -> Result<(), String> {
        if !context.active {
            return Ok(());
        }
        let waiting = self.negotiation_since.get_or_insert_with(Instant::now);
        if self.connection.is_none() && waiting.elapsed() >= Duration::from_secs(15) {
            if !state.snapshot.failed {
                super::diagnose(format_args!(
                    "negotiation expired after {:?}",
                    waiting.elapsed()
                ));
            }
            state.snapshot.failed = true;
            return Ok(());
        }
        if self.connection.is_none() && context.caller {
            self.install(Connection::new(context.clone(), None)?, state)?;
        }
        for signal in state.inbound.drain(..).collect::<Vec<_>>() {
            if self.connection.is_none() {
                if let Signal::Description(offer) = signal {
                    self.install(Connection::new(context.clone(), Some(offer))?, state)?;
                }
                continue;
            }
            let connection = self.connection.as_mut().unwrap();
            if let Signal::Camera { nonce, enabled } = &signal {
                if nonce == &connection.binding.media_session {
                    state.snapshot.remote_camera = *enabled;
                    if !enabled {
                        state.frames[1] = None;
                    }
                }
            }
            connection.apply(signal)?;
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
        if !connection.choices(&state.choices)? {
            state.choices.microphone = false;
        }
        self.choices = state.choices.clone();
        if !connection.context.caller {
            connection.start()?;
        }
        self.connection = Some(connection);
        Ok(())
    }
}

fn present_capture(
    frame: &super::capture::Captured,
    state: &mut State,
    connection: Option<&Connection>,
) {
    if u128::from(frame.source_age_ms) + frame.received.elapsed().as_millis() >= 1000 {
        return;
    }
    if let Some(connection) = connection {
        connection
            .engine
            .push(frame.width, frame.height, &frame.pixels);
    }
    state.preview(frame);
    state.snapshot.camera = true;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_call::capture::Captured;

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
        let mut frame = Captured {
            sequence: 1,
            width: 1,
            height: 1,
            pixels: vec![0; 4],
            received: Instant::now() - Duration::from_millis(1100),
            source_age_ms: 0,
        };
        present_capture(&frame, &mut state, None);
        assert!(!state.snapshot.camera);
        assert!(state.frames[0].is_none());
        frame.received = Instant::now() - Duration::from_millis(600);
        frame.source_age_ms = 500;
        present_capture(&frame, &mut state, None);
        assert!(state.frames[0].is_none());
        frame.received = Instant::now();
        frame.source_age_ms = 0;
        present_capture(&frame, &mut state, None);
        assert!(state.snapshot.camera);
        assert!(state.frames[0].is_some());
    }
}
