mod capture;
mod connection;
mod courier;
mod devices;
mod diagnostics;
mod library;
mod packets;
mod recovery;
mod state;
mod telemetry;
mod texture;
pub(crate) mod types;
mod worker;

pub(crate) use library::{media_protocol, LEGACY_MEDIA_PROTOCOL};

use crate::private_dm_runtime::transport::DmTransport;
use state::State;
use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
pub(crate) use texture::Texture;
use types::{Choices, Context, Frame, Signal, Snapshot, Surface};

/// Reuse the bounded helper inventory without creating an engine or call.
pub(crate) fn list_cameras() -> Result<Vec<types::Device>, String> {
    let mut query = capture::Query::start()?;
    loop {
        if let Some(devices) = query.poll() {
            return devices;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// Owns one selected call independently of Flutter and the presentation process.
pub(crate) struct Hub {
    state: Arc<Mutex<State>>,
}

impl Hub {
    pub fn new(transport: Arc<dyn DmTransport>) -> Result<Arc<Self>, String> {
        transport.enable_call_packets()?;
        let state = Arc::new(Mutex::new(State::default()));
        let owner = state.clone();
        std::thread::Builder::new()
            .name("mosh-native-call".into())
            .spawn(move || worker::run(owner, transport))
            .map_err(|error| error.to_string())?;
        Ok(Arc::new(Self { state }))
    }

    pub fn prepare(&self, context: Context, choices: Choices) -> Result<(), String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "native call state poisoned")?;
        let same = state
            .context
            .as_ref()
            .is_some_and(|old| context.continues(old));
        if !same || !state.prepared {
            state.inbound.clear();
            state.pending_camera_default = choices.camera_id.clone();
            state.choices = choices;
            state.revision = state.revision.saturating_add(1);
        }
        let session = context.session_id.clone();
        let call = context.call_id.clone();
        let revision = state.revision;
        state.context = Some(context);
        state.prepared = true;
        drop(state);
        self.wait_applied(&session, &call, revision)
    }

    pub fn sync(&self, context: Option<Context>, inbound: Vec<Signal>) {
        if let Ok(mut state) = self.state.lock() {
            let same = state
                .context
                .as_ref()
                .zip(context.as_ref())
                .is_some_and(|(old, new)| new.continues(old));
            if !same {
                state.inbound.clear();
                state.outbound.clear();
                state.prepared = false;
                state.pending_camera_default = None;
                state.choices = Default::default();
                // A step that began under the old call must not write its
                // choices back over these.
                state.revision = state.revision.saturating_add(1);
            }
            state.context = context;
            for signal in inbound {
                state.receive(signal);
            }
        }
    }

    /// Hands the choices to the owner and returns once it holds the call
    /// state, without waiting for the owner's next step. The snapshot shows
    /// the request at once and the outcome, such as a refused microphone,
    /// after that step.
    pub fn choices(
        &self,
        session: &str,
        call: &str,
        mut choices: Choices,
        camera_selection: bool,
    ) -> Result<(), String> {
        choices.input = choices
            .input
            .as_deref()
            .map(devices::canonical)
            .map(str::to_owned);
        choices.output = choices
            .output
            .as_deref()
            .map(devices::canonical)
            .map(str::to_owned);
        let mut state = self
            .state
            .lock()
            .map_err(|_| "native call state poisoned")?;
        if !state.prepared
            || !state
                .context
                .as_ref()
                .is_some_and(|ctx| ctx.matches(session, call))
        {
            return Err("call no longer exists".into());
        }
        if state.snapshot.failed {
            return Err("native media failed".into());
        }
        if camera_selection {
            state.pending_camera_default = None;
        } else {
            // Other controls may carry a snapshot from before asynchronous
            // default resolution. Only an explicit camera pick changes it.
            choices.camera_id.clone_from(&state.choices.camera_id);
        }
        state.request(choices);
        Ok(())
    }

    fn wait_applied(&self, session: &str, call: &str, revision: u64) -> Result<(), String> {
        let until = Instant::now() + Duration::from_secs(5);
        loop {
            let state = self
                .state
                .lock()
                .map_err(|_| "native call state poisoned")?;
            if !state
                .context
                .as_ref()
                .is_some_and(|ctx| ctx.matches(session, call))
            {
                return Err("call ended while applying devices".into());
            }
            if state.applied >= revision {
                return if state.snapshot.failed {
                    Err("native media failed to apply device choices".into())
                } else {
                    Ok(())
                };
            }
            if Instant::now() >= until {
                return Err("native device command timed out".into());
            }
            drop(state);
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    pub fn snapshot(&self, session: &str, call: &str) -> Option<Snapshot> {
        let state = self.state.lock().ok()?;
        state
            .context
            .as_ref()?
            .matches(session, call)
            .then(|| state.snapshot.clone())
    }

    pub fn frame(&self, session: &str, call: &str, local: bool, after: u64) -> Option<Frame> {
        let presented = {
            let state = self.state.lock().ok()?;
            if !state.context.as_ref()?.matches(session, call) {
                return None;
            }
            state.frames[if local { 0 } else { 1 }].clone()?
        };
        let age =
            u128::from(presented.frame.source_age_ms) + presented.received.elapsed().as_millis();
        if presented.frame.session_id != session
            || presented.frame.call_id != call
            || presented.frame.sequence <= after
            || age >= 1000
        {
            return None;
        }
        let mut frame = presented.frame.clone();
        frame.source_age_ms = age as u32;
        Some(frame)
    }

    /// Later frames of every call leave at most at these window surfaces.
    pub fn show_at(&self, local: Surface, remote: Surface) -> Result<(), String> {
        self.state
            .lock()
            .map_err(|_| "native call state poisoned")?
            .surfaces = [local, remote];
        Ok(())
    }

    /// Later frames of every call are written into these textures of the
    /// main window; a lane with one hands `frame` nothing.
    pub fn show_in(&self, local: Option<Texture>, remote: Option<Texture>) -> Result<(), String> {
        self.state
            .lock()
            .map_err(|_| "native call state poisoned")?
            .textures = [local, remote];
        Ok(())
    }

    pub fn outbound(&self) -> Vec<(String, String, Signal)> {
        self.state
            .lock()
            .map(|mut state| state.outbound.drain(..).collect())
            .unwrap_or_default()
    }
}
impl Drop for Hub {
    fn drop(&mut self) {
        if let Ok(mut state) = self.state.lock() {
            state.shutdown = true;
        }
    }
}

#[cfg(all(test, feature = "call-video-bench"))]
mod benchmark;
#[cfg(test)]
mod lifecycle_tests;
