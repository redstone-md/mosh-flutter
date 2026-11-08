//! Log media state transitions, not frames, so field logs can locate a stall.
use super::state::State;
use crate::private_dm_runtime::transport::PeerTransport;
use serde::{Serialize, Serializer};
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

/// The longest of one kind of pause.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Longest(pub Duration);

impl Serialize for Longest {
    /// As whole milliseconds, the log's unit for every pause.
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_u128(self.0.as_millis())
    }
}

impl Longest {
    /// Keeps the time since `started` if it is the longest yet.
    pub fn since(&mut self, started: Instant) {
        self.include(Self(started.elapsed()));
    }

    fn include(&mut self, other: Self) {
        self.0 = self.0.max(other.0);
    }
}

/// The longest pauses that hold call media back, logged as `stalls_max_ms`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub(crate) struct Stalls {
    /// One owner step; the phases below are the parts of it that may run long.
    pub step: Longest,
    /// Camera inventory and capture, with the frame handed to the engine.
    pub capture: Longest,
    /// The engine snapshot and the device refresh behind the call's statistics.
    pub statistics: Longest,
    /// The engine tick: ICE candidates and libwebrtc's statistics.
    pub tick: Longest,
    /// Copying the peer's latest frame out of the engine.
    pub present: Longest,
    /// The owner waiting for the call state lock, which Dart's commands and
    /// frame reads also take.
    pub lock_wait: Longest,
    /// Between two passes of the packet thread; its 2 ms interval is the floor.
    pub drain: Longest,
}

impl Stalls {
    pub fn include(&mut self, other: Self) {
        self.step.include(other.step);
        self.capture.include(other.capture);
        self.statistics.include(other.statistics);
        self.tick.include(other.tick);
        self.present.include(other.present);
        self.lock_wait.include(other.lock_wait);
        self.drain.include(other.drain);
    }
}

/// Where outgoing media waits on its way to Moss.
#[derive(Clone, Copy, Default)]
pub(super) struct Pipeline {
    pub sender_dropped: u64,
    pub stalls: Stalls,
}

/// While the engine or the sender keeps dropping packets, log at this pace
/// even when the call's status holds still.
const LOSS_LOG_INTERVAL: Duration = Duration::from_secs(10);

#[derive(Default)]
pub(super) struct Monitor {
    status: Option<Status>,
    captured: Growth,
    heard: Growth,
    /// The longest stalls since the previous line.
    stalls: Stalls,
    logged: Option<(Instant, u64)>,
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
    pub fn update(
        &mut self,
        route: PeerTransport,
        state: &State,
        engine: &Value,
        pipeline: Pipeline,
    ) {
        if let Some(message) = self.observe(route, state, engine, pipeline, Instant::now()) {
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
        pipeline: Pipeline,
        now: Instant,
    ) -> Option<String> {
        self.stalls.include(pipeline.stalls);
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
        let dropped = ["full", "stale"]
            .iter()
            .filter_map(|cause| engine["queue_dropped"][cause].as_u64())
            .sum::<u64>()
            + pipeline.sender_dropped;
        let losing = self.logged.is_some_and(|(at, logged)| {
            dropped > logged && now.saturating_duration_since(at) >= LOSS_LOG_INTERVAL
        });
        if self.status.as_ref() == Some(&status) && !losing {
            return None;
        }
        let metrics = json!({"video_age_ms": age.map(|age| age.min(u128::from(u32::MAX)) as u32),
            "decoded": engine["decoded"], "sender_dropped": pipeline.sender_dropped,
            "engine_dropped": engine["queue_dropped"],
            "stalls_max_ms": self.stalls, "audio": engine["audio"],
            "audio_sender": engine["audio_sender"],
            "video": engine["video"], "encoder": engine["encoder"]});
        let message = status.describe(state, &metrics);
        self.status = Some(status);
        self.stalls = Stalls::default();
        self.logged = Some((now, dropped));
        Some(message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_call::types::Context;
    use std::time::Duration;

    fn sent(sender_dropped: u64) -> Pipeline {
        Pipeline {
            sender_dropped,
            ..Default::default()
        }
    }

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
        let event = monitor
            .observe(route, &state, &engine, sent(0), now)
            .unwrap();
        assert!(event.contains("remote_video=waiting"));
        assert!(monitor
            .observe(route, &state, &engine, sent(0), now)
            .is_none());
        state.present(1, 1, vec![0; 4], 0, now, false);
        let event = monitor
            .observe(route, &state, &engine, sent(0), now)
            .unwrap();
        assert!(event.contains("remote_video=live"));
        let later = now + Duration::from_secs(1);
        let event = monitor
            .observe(route, &state, &engine, sent(7), later)
            .unwrap();
        assert!(event.contains("remote_video=stalled"));
        assert!(event.contains("\"sender_dropped\":7"));
        assert!(monitor
            .observe(route, &state, &engine, sent(8), later)
            .is_none());
        state.present(1, 1, vec![0; 4], 0, later, false);
        let event = monitor
            .observe(route, &state, &engine, sent(8), later)
            .unwrap();
        assert!(event.contains("remote_video=live"));
        state.snapshot.remote_camera = false;
        let event = monitor
            .observe(route, &state, &engine, sent(8), later)
            .unwrap();
        assert!(event.contains("remote_video=off"));
        let event = monitor
            .observe(PeerTransport::Relayed, &state, &engine, sent(8), later)
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
            .observe(route, &state, &engine(1.0, 0.0), sent(0), now)
            .unwrap();
        assert!(event.contains("microphone=true; capturing=true; hearing=false"));
        assert!(event.contains("input=default; output=default"));
        let event = monitor
            .observe(route, &state, &engine(1.0, 2.0), sent(0), now)
            .unwrap();
        assert!(event.contains("capturing=true; hearing=true"));
        let second = now + Duration::from_secs(1);
        assert!(monitor
            .observe(route, &state, &engine(1.0, 2.0), sent(0), second)
            .is_none());
        let later = now + Duration::from_secs(3);
        let event = monitor
            .observe(route, &state, &engine(1.0, 2.0), sent(0), later)
            .unwrap();
        assert!(event.contains("capturing=false; hearing=false"));
    }

    #[test]
    fn losses_are_logged_with_the_longest_stalls_while_status_holds() {
        let now = Instant::now();
        let state = State::default();
        let route = PeerTransport::Direct;
        let engine = |full: u64, stale: u64| json!({"connection":"Connected", "queue_dropped": {"full": full, "stale": stale}});
        let ms = |ms: u64| Longest(Duration::from_millis(ms));
        let stalled = |step_ms: u64, drain_ms: u64| Pipeline {
            stalls: Stalls {
                step: ms(step_ms),
                tick: ms(step_ms / 2),
                lock_wait: ms(step_ms / 10),
                drain: ms(drain_ms),
                ..Default::default()
            },
            ..Default::default()
        };
        let mut monitor = Monitor::default();
        let event = monitor
            .observe(route, &state, &engine(0, 0), stalled(20, 3), now)
            .unwrap();
        assert!(event.contains("\"stalls_max_ms\":{\"capture\":0,\"drain\":3,\"lock_wait\":2,\"present\":0,\"statistics\":0,\"step\":20,\"tick\":10}"));
        let soon = now + Duration::from_secs(9);
        assert!(monitor
            .observe(route, &state, &engine(0, 5), stalled(310, 4), soon)
            .is_none());
        let later = now + Duration::from_secs(10);
        let event = monitor
            .observe(route, &state, &engine(2, 5), stalled(40, 2), later)
            .unwrap();
        assert!(event.contains("\"engine_dropped\":{\"full\":2,\"stale\":5}"));
        assert!(event.contains("\"stalls_max_ms\":{\"capture\":0,\"drain\":4,\"lock_wait\":31,\"present\":0,\"statistics\":0,\"step\":310,\"tick\":155}"));
        let sender_losing = Pipeline {
            sender_dropped: 3,
            ..stalled(40, 2)
        };
        let event = monitor
            .observe(
                route,
                &state,
                &engine(2, 5),
                sender_losing,
                later + Duration::from_secs(10),
            )
            .unwrap();
        assert!(event.contains("\"sender_dropped\":3"));
        let quiet = later + Duration::from_secs(30);
        assert!(
            monitor
                .observe(route, &state, &engine(2, 5), sender_losing, quiet)
                .is_none(),
            "no new losses, no line"
        );
    }
}
