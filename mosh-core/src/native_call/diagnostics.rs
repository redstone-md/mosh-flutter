//! Log media state transitions, not frames, so field logs can locate a stall.
use super::state::State;
use crate::private_dm_runtime::transport::PeerTransport;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[derive(Debug, PartialEq)]
struct Status {
    route: PeerTransport,
    ice: String,
    ready: bool,
    video: &'static str,
    microphone: bool,
    capturing: bool,
    hearing: bool,
}

impl Status {
    fn describe(&self, state: &State, metrics: &Value) -> String {
        let name = |devices: &[super::types::Device], id: &Option<String>| {
            id.as_ref().map_or("default".to_string(), |id| {
                devices
                    .iter()
                    .find(|device| &device.id == id)
                    .map_or_else(|| id.clone(), |device| device.name.clone())
            })
        };
        format!(
            "native media: route={:?}; ice={}; ready={}; remote_video={}; microphone={}; \
             capturing={}; hearing={}; input={}; output={}; metrics={metrics}",
            self.route,
            self.ice,
            self.ready,
            self.video,
            self.microphone,
            self.capturing,
            self.hearing,
            name(&state.snapshot.inputs, &state.choices.input),
            name(&state.snapshot.outputs, &state.choices.output),
        )
    }
}

#[derive(Default)]
pub(super) struct Monitor {
    status: Option<Status>,
    captured: Growth,
    heard: Growth,
}

/// A cumulative audio energy, which only grows while there is sound: a
/// silent device or a missing stream leaves it flat.
#[derive(Default)]
struct Growth {
    total: f64,
    at: Option<Instant>,
}

impl Growth {
    /// Whether the total rose within the last two seconds; the engine
    /// refreshes its statistics once a second.
    fn rising(&mut self, total: Option<f64>, now: Instant) -> bool {
        let total = total.unwrap_or(0.0);
        if total > self.total {
            self.at = Some(now);
        }
        self.total = total;
        self.at
            .is_some_and(|at| now.saturating_duration_since(at) < Duration::from_secs(2))
    }
}

impl Monitor {
    pub fn update(&mut self, route: PeerTransport, state: &State, engine: &Value, dropped: u64) {
        if let Some(message) = self.observe(route, state, engine, dropped, Instant::now()) {
            crate::diagnostics_log::write(
                crate::diagnostics_log::LogLevel::Info,
                crate::diagnostics_log::kinds::CALL,
                &state.snapshot.session_id,
                &message,
            );
        }
    }

    fn observe(
        &mut self,
        route: PeerTransport,
        state: &State,
        engine: &Value,
        dropped: u64,
        now: Instant,
    ) -> Option<String> {
        let age = state.frames[1].as_ref().map(|frame| {
            u128::from(frame.frame.source_age_ms)
                + now.saturating_duration_since(frame.received).as_millis()
        });
        let status = Status {
            route,
            ice: engine["connection"].as_str().unwrap_or("unknown").into(),
            ready: state.snapshot.ready,
            video: match (state.snapshot.remote_camera, age) {
                (false, _) => "off",
                (true, None) => "waiting",
                (true, Some(age)) if age >= 1000 => "stalled",
                _ => "live",
            },
            microphone: engine["microphone"].as_bool().unwrap_or(false),
            capturing: self
                .captured
                .rising(engine["audio_sender"]["microphone_energy"].as_f64(), now),
            hearing: self
                .heard
                .rising(engine["audio"]["total_energy"].as_f64(), now),
        };
        if self.status.as_ref() == Some(&status) {
            return None;
        }
        let metrics = json!({"video_age_ms": age.map(|age| age.min(u128::from(u32::MAX)) as u32),
            "decoded": engine["decoded"], "sender_dropped": dropped,
            "engine_dropped": engine["queue_dropped"], "audio": engine["audio"],
            "audio_sender": engine["audio_sender"],
            "video": engine["video"], "encoder": engine["encoder"]});
        let message = status.describe(state, &metrics);
        self.status = Some(status);
        Some(message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_call::types::Context;
    use std::time::Duration;

    #[test]
    fn video_stall_recovery_camera_off_and_route_changes_log_once() {
        let now = Instant::now();
        let mut state = State {
            context: Some(Context {
                session_id: "dm".into(),
                call_id: "call".into(),
                superseded: None,
                active: true,
                caller: true,
                caller_signer: "a".into(),
                callee_signer: Some("b".into()),
                peer: "peer".into(),
            }),
            ..Default::default()
        };
        state.snapshot.remote_camera = true;
        let engine = json!({"connection":"Connected", "decoded":12});
        let mut monitor = Monitor::default();
        let route = PeerTransport::Direct;
        let event = monitor.observe(route, &state, &engine, 0, now).unwrap();
        assert!(event.contains("remote_video=waiting"));
        assert!(monitor.observe(route, &state, &engine, 0, now).is_none());
        state.present(1, 1, vec![0; 4], 0, now, false);
        let event = monitor.observe(route, &state, &engine, 0, now).unwrap();
        assert!(event.contains("remote_video=live"));
        let later = now + Duration::from_secs(1);
        let event = monitor.observe(route, &state, &engine, 7, later).unwrap();
        assert!(event.contains("remote_video=stalled"));
        assert!(event.contains("\"sender_dropped\":7"));
        assert!(monitor.observe(route, &state, &engine, 8, later).is_none());
        state.present(1, 1, vec![0; 4], 0, later, false);
        let event = monitor.observe(route, &state, &engine, 8, later).unwrap();
        assert!(event.contains("remote_video=live"));
        state.snapshot.remote_camera = false;
        let event = monitor.observe(route, &state, &engine, 8, later).unwrap();
        assert!(event.contains("remote_video=off"));
        let event = monitor
            .observe(PeerTransport::Relayed, &state, &engine, 8, later)
            .unwrap();
        assert!(event.contains("route=Relayed"));
    }

    #[test]
    fn audio_logs_when_the_microphone_or_the_peer_falls_silent() {
        let now = Instant::now();
        let state = State::default();
        let route = PeerTransport::Direct;
        let engine = |mic: f64, heard: f64| {
            json!({"connection":"Connected", "microphone": true,
                "audio_sender": {"microphone_energy": mic}, "audio": {"total_energy": heard}})
        };
        let mut monitor = Monitor::default();
        let event = monitor
            .observe(route, &state, &engine(1.0, 0.0), 0, now)
            .unwrap();
        assert!(event.contains("microphone=true; capturing=true; hearing=false"));
        assert!(event.contains("input=default; output=default"));
        let event = monitor
            .observe(route, &state, &engine(1.0, 2.0), 0, now)
            .unwrap();
        assert!(event.contains("capturing=true; hearing=true"));
        let second = now + Duration::from_secs(1);
        assert!(monitor
            .observe(route, &state, &engine(1.0, 2.0), 0, second)
            .is_none());
        let later = now + Duration::from_secs(3);
        let event = monitor
            .observe(route, &state, &engine(1.0, 2.0), 0, later)
            .unwrap();
        assert!(event.contains("capturing=false; hearing=false"));
    }
}
