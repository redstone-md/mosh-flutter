use super::{library::Engine, packets::Sender, state::State};
use crate::private_dm_runtime::transport::{DmTransport, PeerTransport};
use serde_json::json;
use std::time::{Duration, Instant};

pub(super) struct Reporter {
    statistics: Instant,
    devices_at: Instant,
    disconnected: Option<Instant>,
    budget: u64,
    connected_once: bool,
}
impl Reporter {
    pub fn new() -> Self {
        Self {
            statistics: Instant::now(),
            devices_at: Instant::now(),
            disconnected: None,
            budget: 0,
            connected_once: false,
        }
    }
    fn refresh_devices(&mut self, engine: &mut Engine, state: &mut State) -> Result<(), String> {
        if self.devices_at.elapsed() < Duration::from_secs(2) {
            return Ok(());
        }
        self.devices_at = Instant::now();
        let devices = engine.ask(json!({"action":"devices"}))?;
        state.snapshot.inputs =
            serde_json::from_value(devices["inputs"].clone()).unwrap_or_default();
        state.snapshot.outputs =
            serde_json::from_value(devices["outputs"].clone()).unwrap_or_default();
        let missing = state.snapshot.inputs.is_empty()
            || state
                .choices
                .input
                .as_ref()
                .is_some_and(|id| !state.snapshot.inputs.iter().any(|d| &d.id == id));
        if missing && state.choices.microphone {
            state.choices.microphone = false;
            engine.ask(json!({"action":"choices","microphone":state.choices.microphone && state.choices.microphone_allowed,"video":state.choices.camera}))?;
            engine.ask(json!({"action":"select","input":state.choices.input,"output":state.choices.output}))?;
        }
        if state
            .choices
            .output
            .as_ref()
            .is_some_and(|id| !state.snapshot.outputs.iter().any(|d| &d.id == id))
        {
            state.choices.output = None;
            engine.ask(json!({"action":"choices","microphone":state.choices.microphone && state.choices.microphone_allowed,"video":state.choices.camera}))?;
            engine.ask(json!({"action":"select","input":state.choices.input,"output":state.choices.output}))?;
        }
        Ok(())
    }

    pub fn update(
        &mut self,
        engine: &mut Engine,
        peer: &str,
        ready: bool,
        transport: &dyn DmTransport,
        sender: &Sender,
        state: &mut State,
    ) -> Result<(), String> {
        if self.statistics.elapsed() < Duration::from_millis(250) {
            return Ok(());
        }
        self.statistics = Instant::now();
        self.refresh_devices(engine, state)?;
        let snapshot = engine.ask(json!({"action":"snapshot"}))?;
        state.snapshot.packets_dropped = sender.dropped();
        let route = transport.reach(peer);
        let connected = matches!(
            snapshot["connection"].as_str(),
            Some("Connected" | "Completed")
        ) && route != PeerTransport::None;
        if state.snapshot.ready != (ready && connected) {
            super::diagnose(format_args!(
                "ready={} negotiated={ready} ice={} route={route:?}",
                connected, snapshot["connection"]
            ));
        }
        state.snapshot.ready = ready && connected;
        self.connected_once |= connected;
        state.snapshot.reconnecting = self.connected_once && !state.snapshot.ready;
        let expired = super::recovery::expired(&mut self.disconnected, connected, Instant::now());
        if expired && !state.snapshot.failed {
            super::diagnose(format_args!(
                "connection expired: negotiated={ready} ice={} route={route:?}",
                snapshot["connection"]
            ));
        }
        state.snapshot.failed = expired;
        sender.relayed(route == PeerTransport::Relayed);
        let budget = if route == PeerTransport::Relayed {
            320_000
        } else {
            3_000_000
        };
        if self.budget != budget {
            engine.ask(json!({"action":"budget","max_bps":budget}))?;
            self.budget = budget;
        }
        let encoder = &snapshot["encoder"];
        state.snapshot.encoder = encoder["implementation"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(str::to_string);
        state.snapshot.codec = encoder["codec"].as_str().map(str::to_string);
        state.snapshot.video_width = encoder["width"].as_u64().unwrap_or(0) as u32;
        state.snapshot.video_height = encoder["height"].as_u64().unwrap_or(0) as u32;
        state.snapshot.video_fps = encoder["fps"].as_f64().unwrap_or(0.0);
        Ok(())
    }
}
