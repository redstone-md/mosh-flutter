use super::*;
use std::collections::VecDeque;

const RETRY_WINDOW_MS: u64 = 15_000;
const MAX_TERMINAL_CONTROLS: usize = 32;

#[derive(Default)]
pub(in crate::private_dm_runtime) struct CallEndRetries {
    controls: VecDeque<TerminalControl>,
}

struct TerminalControl {
    call_id: String,
    action: CallAction,
    expires: u64,
    last_sent: u64,
}

impl CallEndRetries {
    pub(super) fn remember(&mut self, call_id: &str, action: CallAction, now: u64) {
        self.controls
            .retain(|control| control.call_id != call_id && control.expires > now);
        if self.controls.len() == MAX_TERMINAL_CONTROLS {
            self.controls.pop_front();
        }
        self.controls.push_back(TerminalControl {
            call_id: call_id.into(),
            action,
            expires: now.saturating_add(RETRY_WINDOW_MS),
            last_sent: now,
        });
    }

    pub(super) fn due(&mut self, now: u64) -> Vec<(String, CallAction)> {
        self.controls.retain(|control| control.expires > now);
        self.controls
            .iter_mut()
            .filter_map(|control| {
                if now.saturating_sub(control.last_sent) < CALL_RESEND_MS {
                    return None;
                }
                control.last_sent = now;
                Some((control.call_id.clone(), control.action.clone()))
            })
            .collect()
    }
}
