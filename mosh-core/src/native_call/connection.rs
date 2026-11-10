use super::{
    devices::Selection,
    library::{Engine, MAX_RGBA},
    packets::Sender,
    state::State,
    types::{Binding, Choices, Context, Description, Signal, Surface},
};
use crate::private_dm_runtime::transport::DmTransport;
use rand::RngCore;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

pub(crate) struct Connection {
    pub context: Context,
    pub binding: Binding,
    pub engine: Engine,
    local: Description,
    ready: bool,
    candidates: Vec<String>,
    pending: Vec<String>,
    resend: Instant,
    reporter: super::telemetry::Reporter,
    last_decoded: u64,
    pixels: Vec<u8>,
    /// The remote surface the engine scales decoded frames to.
    shown: Surface,
    selection: Selection,
}

impl Connection {
    /// The engine's packets travel over a link from `sender`, never through `pump`.
    pub fn new(
        context: Context,
        offer: Option<Description>,
        sender: &Sender,
    ) -> Result<Self, String> {
        let mut nonce = vec![0; 16];
        rand::thread_rng().fill_bytes(&mut nonce);
        let binding = offer
            .as_ref()
            .map(|offer| offer.binding.clone())
            .or_else(|| context.binding(nonce))
            .ok_or("call is not selected")?;
        if context.binding(binding.media_session.clone()).as_ref() != Some(&binding)
            || offer
                .as_ref()
                .is_some_and(|offer| !offer.offer || context.caller)
        {
            return Err("media description does not match the selected pair".into());
        }
        let wire = sender.link(&context.peer, &binding.media_session);
        let mut engine = Engine::new(&binding, context.caller, wire)?;
        let local = parse_local(if let Some(offer) = offer {
            engine.ask(json!({"action":"remote","description":offer}))?
        } else {
            engine.ask(json!({"action":"offer"}))?
        })?;
        Ok(Self {
            context,
            binding,
            engine,
            local,
            ready: false,
            candidates: Vec::new(),
            pending: Vec::new(),
            resend: Instant::now() - Duration::from_secs(2),
            reporter: super::telemetry::Reporter::new(),
            last_decoded: 0,
            pixels: vec![0; MAX_RGBA],
            shown: Surface::default(),
            selection: Selection::default(),
        })
    }

    pub fn apply(&mut self, signal: Signal, state: &mut State) -> Result<(), String> {
        match signal {
            Signal::Description(description) => {
                if description.binding != self.binding || description.offer == self.context.caller {
                    return Ok(());
                }
                let local = self
                    .engine
                    .ask(json!({"action":"remote","description":description}))?;
                self.adopt(local)?;
                // The caller repeats an offer until it hears back, so the
                // callee answers every one, a path of its own or not.
                if !self.context.caller {
                    self.announce(state);
                }
                self.start()?;
            }
            Signal::Candidates { nonce, candidates } if nonce == self.binding.media_session => {
                for candidate in candidates {
                    if self.pending.len() < 32 && !self.pending.contains(&candidate) {
                        self.pending.push(candidate);
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }

    pub fn start(&mut self) -> Result<(), String> {
        if self.ready {
            return Ok(());
        }
        self.engine.ask(json!({"action":"start"}))?;
        self.ready = true;
        Ok(())
    }

    /// Applies the switches and, for a new pick, the audio devices. Whether
    /// the picked input is usable.
    pub fn choices(&mut self, choices: &Choices) -> Result<bool, String> {
        self.engine.ask(
            json!({"action":"choices", "microphone":choices.microphone && choices.microphone_allowed,"video":choices.camera}),
        )?;
        let engine = &mut self.engine;
        self.selection.apply(choices, || {
            let selected = engine
                .ask(json!({"action":"select","input":choices.input,"output":choices.output}))?;
            Ok(["input_ok", "output_ok"].map(|ok| selected[ok].as_bool().unwrap_or(false)))
        })
    }

    pub fn pump(
        &mut self,
        transport: &dyn DmTransport,
        sender: &Sender,
        state: &mut State,
    ) -> Result<(), String> {
        let measuring = Instant::now();
        self.reporter.update(
            &mut self.engine,
            &self.context.peer,
            self.ready,
            transport,
            sender,
            state,
        )?;
        state.stalls.statistics.since(measuring);
        if self.reporter.take_ice_failure() && self.context.caller {
            self.restart_ice(state)?;
        }
        let candidates = if self.ready {
            std::mem::take(&mut self.pending)
        } else {
            Vec::new()
        };
        let ticking = Instant::now();
        let gathered = self
            .engine
            .ask(json!({"action":"tick","candidates":candidates}))?;
        state.stalls.tick.since(ticking);
        self.gather(&gathered["candidates"]);
        let presenting = Instant::now();
        self.show_at(state.surfaces[1])?;
        self.present(state);
        state.stalls.present.since(presenting);
        if self.resend.elapsed() >= Duration::from_secs(1) {
            self.resend = Instant::now();
            if !state.snapshot.ready {
                self.announce(state);
            }
            state.emit(Signal::Camera {
                nonce: self.binding.media_session.clone(),
                enabled: state.snapshot.camera,
            });
        }
        Ok(())
    }

    /// A failed path never recovers without new ICE credentials. Only the
    /// caller restarts, so the two sides never restart at once.
    pub(super) fn restart_ice(&mut self, state: &mut State) -> Result<(), String> {
        use crate::diagnostics_log::{kinds, write, LogLevel};
        let session = &self.context.session_id;
        write(
            LogLevel::Info,
            kinds::CALL,
            session,
            "ICE failed; restarting it",
        );
        let offer = self.engine.ask(json!({"action":"restart"}))?;
        self.adopt(offer)?;
        self.announce(state);
        Ok(())
    }

    /// Takes the engine's local description. A new one, a restart offer or
    /// its answer, carries new ICE credentials, so the old candidates go.
    fn adopt(&mut self, local: Value) -> Result<(), String> {
        let local = parse_local(local)?;
        if local != self.local {
            self.local = local;
            self.candidates.clear();
        }
        Ok(())
    }

    /// Keeps up to eight of the candidates the engine gathered, once each.
    fn gather(&mut self, gathered: &Value) {
        for candidate in gathered
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
        {
            if self.candidates.len() < 8 && !self.candidates.iter().any(|known| known == candidate)
            {
                self.candidates.push(candidate.into());
            }
        }
    }

    /// Sends this side's description and the candidates gathered for it.
    fn announce(&self, state: &mut State) {
        state.emit(Signal::Description(self.local.clone()));
        if !self.candidates.is_empty() {
            state.emit(Signal::Candidates {
                nonce: self.binding.media_session.clone(),
                candidates: self.candidates.clone(),
            });
        }
    }

    fn show_at(&mut self, surface: Surface) -> Result<(), String> {
        if surface != self.shown {
            self.engine
                .ask(json!({"action":"surface","width":surface.width,"height":surface.height}))?;
            self.shown = surface;
        }
        Ok(())
    }

    fn present(&mut self, state: &mut State) {
        if let Some(info) = self.engine.frame(self.last_decoded, &mut self.pixels) {
            self.last_decoded = info.sequence;
            if !state.snapshot.remote_camera {
                return;
            }
            state.present(
                info.width,
                info.height,
                self.pixels[..info.rgba_bytes as usize].to_vec(),
                info.age_ms,
                Instant::now(),
                false,
            );
        }
    }
}

fn parse_local(value: Value) -> Result<Description, String> {
    serde_json::from_value(value).map_err(|error| error.to_string())
}
