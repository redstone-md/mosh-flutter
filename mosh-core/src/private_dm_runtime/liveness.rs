//! Whether the counterpart is still there, and what the field log says
//! about it. A slow or flapping Connect is diagnosed from these lines: when
//! the path appeared, when it changed, and how long the silence was that
//! took Connected away.

use super::*;

impl PrivateDmSession {
    /// Stamp the proof drained since the last tick, and admit the
    /// counterpart is gone once nothing authenticated arrived for the whole
    /// lost window. Moss's peer table plays no part: gossip carries a chat
    /// through other peers while moss lists no row for the counterpart, and a
    /// failed mesh report says nothing about the counterpart at all.
    pub(super) fn pump_liveness(&mut self, now_ms: u64, lost_window_ms: u64) {
        if std::mem::take(&mut self.authenticated_since_tick) {
            self.last_authenticated_rx_ms = self.last_authenticated_rx_ms.max(now_ms);
        }
        let silent_for = now_ms.saturating_sub(self.last_authenticated_rx_ms);
        if self.state == DmSessionState::Connected && silent_for >= lost_window_ms {
            self.state = next_state(self.state, SessionEvent::CounterpartLost);
            dlog::write(
                LogLevel::Warn,
                kinds::HANDSHAKE,
                &self.session_id,
                &format!(
                    "session lost: no authenticated frame for {silent_for}ms (reach {:?})",
                    self.reach()
                ),
            );
        }
    }

    /// Log the path to the counterpart whenever it changes: the first one
    /// found after a start is when discovery finished, and a flip between
    /// direct, relayed and none explains a Connected that comes and goes.
    ///
    /// One mesh report per call: a failed one says nothing about the
    /// counterpart, and a second read could land on a restart the first
    /// missed, logging a lost path and a recovery that never happened.
    pub(super) fn pump_reach_log(&mut self) {
        let Some(info) = self.transport.mesh_info() else {
            return;
        };
        let reach = self.reach_in(&info);
        if reach == self.logged_reach {
            return;
        }
        dlog::write(
            LogLevel::Info,
            kinds::CONNECT,
            &self.session_id,
            &format!("peer reach {:?} -> {reach:?}", self.logged_reach),
        );
        self.logged_reach = reach;
    }
}
