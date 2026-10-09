use super::{
    library::{Engine, MAX_PACKET, MAX_RGBA},
    packets::{self, Sender},
    state::State,
    types::{Binding, Choices, Context, Description, Signal},
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
}

impl Connection {
    pub fn new(context: Context, offer: Option<Description>) -> Result<Self, String> {
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
        let mut engine = Engine::new(&binding, context.caller)?;
        let local = if let Some(offer) = offer {
            engine.ask(json!({"action":"remote","description":offer}))?
        } else {
            engine.ask(json!({"action":"offer"}))?
        };
        let local: Description =
            serde_json::from_value(local).map_err(|error| error.to_string())?;
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
        })
    }

    pub fn apply(&mut self, signal: Signal) -> Result<(), String> {
        match signal {
            Signal::Description(description) => {
                if description.binding != self.binding || description.offer == self.context.caller {
                    return Ok(());
                }
                self.engine
                    .ask(json!({"action":"remote","description":description}))?;
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

    pub fn choices(&mut self, choices: &Choices) -> Result<bool, String> {
        self.engine.ask(
            json!({"action":"choices", "microphone":choices.microphone && choices.microphone_allowed,"video":choices.camera}),
        )?;
        let selected = self
            .engine
            .ask(json!({"action":"select","input":choices.input,"output":choices.output}))?;
        Ok(selected["input_ok"].as_bool().unwrap_or(false))
    }

    pub fn pump(
        &mut self,
        transport: &dyn DmTransport,
        sender: &Sender,
        state: &mut State,
    ) -> Result<(), String> {
        let candidates = if self.ready {
            std::mem::take(&mut self.pending)
        } else {
            Vec::new()
        };
        let gathered = self
            .engine
            .ask(json!({"action":"tick","candidates":candidates}))?;
        for candidate in gathered["candidates"]
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
        self.transfer_packets(transport, sender);
        self.present(state);
        self.reporter.update(
            &mut self.engine,
            &self.context.peer,
            self.ready,
            transport,
            sender,
            state,
        )?;
        if self.resend.elapsed() >= Duration::from_secs(1) {
            self.resend = Instant::now();
            if !state.snapshot.ready {
                state.emit(Signal::Description(self.local.clone()));
            }
            if !self.candidates.is_empty() && !state.snapshot.ready {
                state.emit(Signal::Candidates {
                    nonce: self.binding.media_session.clone(),
                    candidates: self.candidates.clone(),
                });
            }
            state.emit(Signal::Camera {
                nonce: self.binding.media_session.clone(),
                enabled: state.snapshot.camera,
            });
        }
        Ok(())
    }

    fn transfer_packets(&mut self, transport: &dyn DmTransport, sender: &Sender) {
        for message in transport.drain_call_packets() {
            if message
                .channel
                .strip_prefix(crate::moss_ffi::PACKET_INBOX_CHANNEL_PREFIX)
                != Some(&self.context.peer)
            {
                continue;
            }
            if let Some(packet) = packets::unwrap(&message.payload, &self.binding.media_session) {
                self.engine.receive(packet);
            }
        }
        let mut packet = [0; MAX_PACKET];
        for _ in 0..128 {
            let Some(length) = self.engine.packet(&mut packet) else {
                break;
            };
            sender.enqueue(
                &self.context.peer,
                &self.binding.media_session,
                &packet[..length],
                self.engine.priority(&packet[..length]),
            );
        }
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
