mod capture;
mod connection;
mod devices;
mod library;
mod packets;
mod recovery;
mod state;
mod telemetry;
pub(crate) mod types;
mod worker;

// Temporary CI probe; no descriptions, keys, device IDs or frame bytes.
pub(super) fn diagnose(message: std::fmt::Arguments<'_>) {
    if std::env::var_os("MOSH_NATIVE_DIAGNOSTICS").is_some() {
        eprintln!("[DEBUG-46] {message}");
    }
}

use crate::private_dm_runtime::transport::DmTransport;
use state::State;
use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use types::{Choices, Context, Frame, Signal, Snapshot};

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
        let same = state.context.as_ref().is_some_and(|old| {
            old.session_id == context.session_id
                && (old.call_id == context.call_id
                    || context.superseded.as_ref() == Some(&old.call_id))
        });
        if !same || !state.prepared {
            state.inbound.clear();
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
                .is_some_and(|(old, new)| {
                    old.session_id == new.session_id
                        && (old.call_id == new.call_id
                            || new.superseded.as_ref() == Some(&old.call_id))
                });
            if !same {
                state.inbound.clear();
                state.prepared = false;
                state.choices = Default::default();
            }
            state.context = context;
            for signal in inbound {
                if state.inbound.len() >= 16 {
                    state.inbound.pop_front();
                }
                state.inbound.push_back(signal);
            }
        }
    }

    pub fn choices(&self, session: &str, call: &str, mut choices: Choices) -> Result<(), String> {
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
        let revision = {
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
            state.choices = choices;
            state.revision = state.revision.saturating_add(1);
            state.revision
        };
        self.wait_applied(session, call, revision)
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

#[cfg(test)]
mod lifecycle_tests;
