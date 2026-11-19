//! Waking a counterpart's iPhone through the wake service (see
//! conversation::wake). A device that has a call ringing or texts it has
//! not acknowledged while it is away asks Dart to send the service a wake;
//! the texts' wakes are in wake_preview.rs.

use super::*;
use crate::conversation::wake::preview::{PreviewKeys, TextWakes};
pub use crate::conversation::wake::{WakeAddress, WakeRequest};
use crate::conversation::wake::{WakeAnnouncement, WakeSetup};
use std::collections::{BTreeMap, BTreeSet};

/// A call wakes a device not heard for a keepalive and a little more: the
/// lost window would leave the woken phone seconds of a 30-second ring.
/// Waking one that was only slow costs a second ring of the same call.
const CALL_QUIET_MS: u64 = KEEPALIVE_MS + 2_000;

/// One session's wake bookkeeping. Only `peers` and `own_keys` are
/// persisted.
#[derive(Default)]
pub(super) struct WakeBook {
    /// Each counterpart device's latest announcement, by its MLS signer.
    pub(super) peers: BTreeMap<String, WakeAnnouncement>,
    /// This device's preview keys for the chat.
    pub(super) own_keys: PreviewKeys,
    /// What this device last announced and in which epoch. Cleared when the
    /// counterpart connects, so it hears the address again.
    pub(super) announced: Option<(WakeAnnouncement, Option<u64>)>,
    heard_since_tick: BTreeSet<String>,
    heard_at: HashMap<String, u64>,
    call_woken: Option<(String, BTreeSet<String>)>,
    pub(super) texts: TextWakes,
    pub(super) due: Vec<WakeRequest>,
}

impl WakeBook {
    /// Keeps `announcement` when it is valid and newer than the one held.
    pub(super) fn accept(&mut self, signer: String, announcement: WakeAnnouncement) -> bool {
        if !announcement.supersedes(self.peers.get(&signer)) {
            return false;
        }
        self.peers.insert(signer, announcement);
        true
    }

    /// An authenticated frame from `signer` arrived; the tick stamps it.
    pub(super) fn heard(&mut self, signer: &[u8]) {
        self.heard_since_tick.insert(hex::encode(signer));
    }

    fn stamp(&mut self, now: u64) {
        for signer in std::mem::take(&mut self.heard_since_tick) {
            self.heard_at.insert(signer, now);
        }
    }

    fn absent(&self, signer: &str, now: u64, quiet: u64) -> bool {
        now.saturating_sub(self.heard_at.get(signer).copied().unwrap_or(0)) >= quiet
    }

    /// Whether `signer` still needs a wake for `call_id`; marks it woken.
    fn mark_call(&mut self, call_id: &str, signer: &str) -> bool {
        if self.call_woken.as_ref().is_none_or(|(id, _)| id != call_id) {
            self.call_woken = Some((call_id.to_string(), BTreeSet::new()));
        }
        let (_, woken) = self.call_woken.as_mut().expect("set above");
        woken.insert(signer.to_string())
    }

    /// Drops every announcement of `handle`; true when one was held.
    fn forget(&mut self, handle: &str) -> bool {
        let before = self.peers.len();
        self.peers
            .retain(|_, held| held.wake_address.handle != handle);
        self.peers.len() != before
    }
}

impl PrivateDmSession {
    /// The tick's wake work: stamp who was heard, announce our own address,
    /// and queue wakes for a ringing call or waiting texts.
    pub(super) fn pump_wake(&mut self, now: u64, setup: &WakeSetup, lost_window: u64) {
        self.wake.stamp(now);
        if let Some(own) = &setup.own {
            self.announce_wake(own, now);
        }
        self.wake_for_call(now, setup);
        self.wake_for_messages(now, lost_window, setup);
    }

    fn announce_wake(&mut self, own: &WakeAddress, now: u64) {
        let epoch = self.crypto.epoch();
        if self.state != DmSessionState::Connected || !self.can_encrypt_for_peer() {
            return;
        }
        let preview_key = if own.withdrawn() {
            None
        } else {
            self.record_dirty |= self.wake.own_keys.rotate(now);
            self.wake.own_keys.current().map(str::to_string)
        };
        let body = WakeAnnouncement {
            wake_address: own.clone(),
            issued_at_ms: now,
            preview_key,
        };
        if !body.due_after(self.wake.announced.as_ref(), epoch) {
            return;
        }
        let Ok(wake_ciphertext_b64) = self.crypto.encrypt_json(&body) else {
            return;
        };
        let envelope = ControlEnvelope::WakeAddress {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            wake_ciphertext_b64,
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        if self.route_send(ChannelKind::Control, &payload).is_ok() {
            self.wake.announced = Some((body, epoch));
            self.log_wake("wake address announced");
        }
    }

    /// A counterpart device's announcement. MLS proves which member wrote it.
    pub(super) fn accept_wake_address(
        &mut self,
        ciphertext_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let (body, signer) = self.crypto.decrypt_with_signer(&decode(ciphertext_b64)?)?;
        let signer_hex = hex::encode(&signer);
        if self.is_own_signer(&signer_hex) {
            return Ok(());
        }
        self.wake.heard(&signer);
        self.note_authenticated_frame("");
        let announcement: WakeAnnouncement = decode_json(&body)?;
        let withdrawn = announcement.wake_address.withdrawn();
        if self.wake.accept(signer_hex, announcement) {
            self.record_dirty = true;
            self.log_wake(if withdrawn {
                "counterpart withdrew its wake address"
            } else {
                "counterpart wake address kept"
            });
        } else {
            self.log_wake("counterpart wake address stale or refused");
        }
        Ok(())
    }

    pub(super) fn log_wake(&self, line: &str) {
        dlog::write(LogLevel::Info, kinds::WAKE, &self.session_id, line);
    }

    fn is_own_signer(&self, signer: &str) -> bool {
        *signer == hex::encode(self.crypto.signer_public())
            || self
                .membership
                .as_ref()
                .is_some_and(|membership| membership.call_own(signer))
    }

    /// Counterpart devices with a live address on this build's service.
    fn wakeable<'a>(
        &'a self,
        setup: &'a WakeSetup,
    ) -> impl Iterator<Item = (&'a String, &'a WakeAnnouncement)> + 'a {
        self.wake
            .peers
            .iter()
            .filter(move |(signer, held)| setup.reaches(held) && !self.is_own_signer(signer))
    }

    /// Whether some counterpart device that is not connected can be woken
    /// through this build's service, so a call may ring it.
    pub(super) fn can_wake_counterpart(&self, setup: &WakeSetup) -> bool {
        self.peer_joined && self.crypto.is_ready() && self.wakeable(setup).next().is_some()
    }

    /// Counterpart devices wakeable through this build's service and not
    /// heard for `quiet`.
    pub(super) fn wake_targets(
        &self,
        now: u64,
        quiet: u64,
        setup: &WakeSetup,
    ) -> Vec<(String, WakeAnnouncement)> {
        self.wakeable(setup)
            .filter(|(signer, _)| self.wake.absent(signer, now, quiet))
            .map(|(signer, held)| (signer.clone(), held.clone()))
            .collect()
    }

    fn wake_for_call(&mut self, now: u64, setup: &WakeSetup) {
        let Some(call_id) = self
            .call
            .as_ref()
            .filter(|call| {
                call.direction == CallDirection::Caller && call.phase == CallPhase::Outgoing
            })
            .map(|call| call.call_id.clone())
        else {
            return;
        };
        for (signer, held) in self.wake_targets(now, CALL_QUIET_MS, setup) {
            if self.wake.mark_call(&call_id, &signer) {
                let request =
                    held.wake_address
                        .request(&self.session_id, Some(call_id.clone()), None);
                self.wake.due.push(request);
                self.log_wake(&format!("wake requested for call {call_id}"));
            }
        }
    }
}

impl PrivateDmRuntime {
    /// This device's wake address, announced in every chat. An empty handle
    /// withdraws it; never calling this announces nothing.
    pub fn set_wake_address(&mut self, address: WakeAddress) {
        self.wake.own = Some(address);
    }

    /// Everything known of waking so far, for a runtime starting now.
    pub(crate) fn set_wake(&mut self, setup: WakeSetup) {
        self.wake = setup;
    }

    /// The one wake service this build wakes contacts through.
    pub fn set_wake_service(&mut self, service: String) {
        self.wake.service = Some(service);
    }

    /// The wakes asked for since the last call, for Dart to send.
    pub fn take_wake_requests(&mut self) -> Vec<WakeRequest> {
        self.sessions
            .values_mut()
            .flat_map(|session| std::mem::take(&mut session.wake.due))
            .collect()
    }

    /// The service no longer knows `handle`: stop waking it.
    pub fn forget_wake_handle(&mut self, handle: &str) {
        for session in self.sessions.values_mut() {
            if session.wake.forget(handle) {
                session.record_dirty = true;
                session.log_wake("wake service no longer knows a counterpart handle");
            }
        }
    }
}

#[cfg(test)]
#[path = "wake_tests.rs"]
pub(super) mod tests;
