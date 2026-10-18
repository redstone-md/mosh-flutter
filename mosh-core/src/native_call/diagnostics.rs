//! Log media state transitions, not frames, so field logs can locate a stall.
use super::state::State;
use crate::private_dm_runtime::transport::PeerTransport;
use serde_json::{json, Value};
use std::time::Instant;

#[derive(Debug, PartialEq)]
struct Status {
    route: PeerTransport,
    ice: String,
    ready: bool,
    video: &'static str,
}

#[derive(Default)]
pub(super) struct Monitor(Option<Status>);

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
        };
        if self.0.as_ref() == Some(&status) {
            return None;
        }
        let message = format!(
            "native media: route={:?}; ice={}; ready={}; remote_video={}; metrics={}",
            status.route,
            status.ice,
            status.ready,
            status.video,
            json!({"video_age_ms": age.map(|age| age.min(u128::from(u32::MAX)) as u32),
                "decoded": engine["decoded"], "sender_dropped": dropped,
                "engine_dropped": engine["queue_dropped"], "audio": engine["audio"],
                "video": engine["video"], "encoder": engine["encoder"]})
        );
        self.0 = Some(status);
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
}
