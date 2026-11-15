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

    pub fn include(&mut self, other: Self) {
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
    /// Applying the user's switches and device picks to the engine.
    pub choices: Longest,
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
        self.choices.include(other.choices);
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

/// A connected call whose sound stops this long is reported as a failure.
const SILENCE_REPORT_AFTER: Duration = Duration::from_secs(10);

#[derive(Default)]
pub(super) struct Monitor {
    status: Option<Status>,
    captured: Growth,
    heard: Growth,
    /// The peer's audio packets, which keep coming while the peer is muted.
    arriving: Growth,
    /// The longest stalls since the previous line.
    stalls: Stalls,
    logged: Option<(Instant, u64)>,
    microphone_silence: Silence,
    peer_silence: Silence,
}

/// How long one side of a connected call has been without sound, told once
/// per call.
#[derive(Default)]
struct Silence {
    since: Option<Instant>,
    reported: bool,
}

impl Silence {
    /// Whether `silent` has now held for `SILENCE_REPORT_AFTER`; true once.
    fn lasted(&mut self, silent: bool, now: Instant) -> bool {
        if !silent {
            self.since = None;
            return false;
        }
        let since = *self.since.get_or_insert(now);
        if self.reported || now.saturating_duration_since(since) < SILENCE_REPORT_AFTER {
            return false;
        }
        self.reported = true;
        true
    }
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
        use crate::diagnostics_log::{kinds, report_failure, write, LogLevel};
        let now = Instant::now();
        let session = &state.snapshot.session_id;
        if let Some(message) = self.observe(route, state, engine, pipeline, now) {
            write(LogLevel::Info, kinds::CALL, session, &message);
        }
        for silence in self.silences(engine, now) {
            report_failure(kinds::CALL, session, &silence);
        }
    }

    /// The sides of a connected call that stayed silent past the limit, each
    /// told once. A muted microphone is not silence; a muted peer still sends
    /// packets, so only their absence counts.
    fn silences(&mut self, engine: &Value, now: Instant) -> Vec<String> {
        let Some(status) = &self.status else {
            return Vec::new();
        };
        // As the reporter's reconnect logic counts it (telemetry.rs).
        let connected = status.ready && matches!(status.ice.as_str(), "Connected" | "Completed");
        let microphone_silent = connected && status.microphone && !status.capturing;
        let arriving = self
            .arriving
            .rising(engine["audio"]["packets_received"].as_f64(), now);
        let limit = SILENCE_REPORT_AFTER.as_secs();
        [
            (
                self.microphone_silence.lasted(microphone_silent, now),
                "the microphone captured no sound",
            ),
            (
                self.peer_silence.lasted(connected && !arriving, now),
                "no audio packets arrived from the peer",
            ),
        ]
        .into_iter()
        .filter(|(lasted, _)| *lasted)
        .map(|(_, silence)| format!("call audio: {silence} for {limit} s"))
        .collect()
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
        let age = state.shown[1].map(|shown| shown.age_ms(now));
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
#[path = "diagnostics_tests.rs"]
mod tests;
