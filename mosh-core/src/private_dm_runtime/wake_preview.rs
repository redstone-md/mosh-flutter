//! Waking a counterpart's phone for texts it has not acknowledged, with
//! previews of them sealed under its key for this chat (see
//! conversation::wake::preview).

use super::*;
use crate::conversation::wake::preview::{seal, PreviewChat};
use crate::conversation::wake::WakeSetup;
use std::collections::BTreeSet;

impl PrivateDmSession {
    /// Wakes an absent counterpart for texts it has not acknowledged: queued
    /// ones, and ones sent while it still looked connected (a phone that just
    /// went to sleep stays Connected for the lost window). Each wake carries
    /// the texts no wake carried before, sealed for the device it goes to.
    pub(super) fn wake_for_messages(&mut self, now: u64, lost_window: u64, setup: &WakeSetup) {
        let waiting: BTreeSet<String> = self
            .outbound_attempts
            .iter()
            .filter(|(_, attempt)| {
                matches!(
                    attempt.delivery_status,
                    MessageDeliveryStatus::Queued | MessageDeliveryStatus::Sent
                )
            })
            .map(|(id, _)| id.clone())
            .collect();
        if waiting.is_empty() {
            return;
        }
        for (signer, held) in self.wake_targets(now, lost_window, setup) {
            let wakes = self.wake.texts.entry(signer).or_default();
            if !wakes.due(&waiting, now) {
                continue;
            }
            let fresh = wakes.carry(waiting.clone(), now);
            let preview = held
                .preview_key
                .as_deref()
                .and_then(|key| seal(key, &self.texts_of(&fresh), None));
            let request = held.wake_address.request(&self.session_id, None, preview);
            self.wake.due.push(request);
            self.log_wake("wake requested for unacknowledged texts");
        }
    }

    /// The texts of `ids`, oldest first.
    fn texts_of(&self, ids: &BTreeSet<String>) -> Vec<String> {
        let mut fresh: Vec<_> = ids
            .iter()
            .filter_map(|id| self.outbound_attempts.get(id))
            .filter_map(|attempt| {
                let message: ChatMessage = serde_json::from_str(&attempt.message_json).ok()?;
                Some((attempt.sent_at_ms, message.body))
            })
            .collect();
        fresh.sort_by_key(|(sent_at, _)| *sent_at);
        fresh.into_iter().map(|(_, body)| body).collect()
    }
}

impl PrivateDmRuntime {
    /// The service refused a texts wake to `handle` in `chat` for good: the
    /// texts it carried first go with the next wake to that device.
    pub fn wake_refused(&mut self, chat: &str, handle: &str) {
        let Some(session) = self.sessions.get_mut(chat) else {
            return;
        };
        let wake = &mut session.wake;
        for signer in wake.devices.with_handle(handle) {
            if let Some(texts) = wake.texts.get_mut(signer) {
                texts.give_back();
            }
        }
    }

    /// The chats this device announced a preview key in; the API names them
    /// as the user does.
    pub fn preview_chats(&self) -> Vec<PreviewChat> {
        self.sessions
            .values()
            .filter(|session| session.wake.own.keys.current().is_some())
            .map(|session| PreviewChat {
                chat_id: session.session_id.clone(),
                name: session.peer_display_name.clone().unwrap_or_default(),
                keys: session.wake.own.keys.opening(),
                members: None,
            })
            .collect()
    }
}

#[cfg(test)]
#[path = "wake_preview_tests.rs"]
mod tests;
