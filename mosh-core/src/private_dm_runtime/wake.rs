//! Waking a counterpart's iPhone through the wake service (see
//! conversation::wake). A device that has a call ringing or texts it has
//! not acknowledged while it is away asks Dart to send the service a wake;
//! the texts' wakes are in wake_preview.rs.

use super::*;
use crate::conversation::wake::preview::TextWakes;
use crate::conversation::wake::{Devices, OwnWake, WakeAnnouncement, WakeSetup};
pub use crate::conversation::wake::{WakeAddress, WakeRequest};
use std::collections::{BTreeMap, BTreeSet};

/// A call wakes a device not heard for a keepalive and a little more: the
/// lost window would leave the woken phone seconds of a 30-second ring.
/// Waking one that was only slow costs a second ring of the same call.
const CALL_QUIET_MS: u64 = KEEPALIVE_MS + 2_000;

/// An unchanged announcement is repeated this often.
const ANNOUNCE_EVERY_MS: u64 = 6 * 60 * 60 * 1000;

/// One session's wake bookkeeping. Only the devices' announcements and
/// this device's keys are persisted.
pub(super) struct WakeBook {
    /// The counterpart's devices; a device never heard counts as unheard
    /// since ever, so a call can wake it at once.
    pub(super) devices: Devices,
    /// This device's announcement in the chat. Announced again when the
    /// counterpart connects, so it hears the address.
    pub(super) own: OwnWake,
    call_woken: Option<(String, BTreeSet<String>)>,
    pub(super) texts: TextWakes,
    pub(super) due: Vec<WakeRequest>,
}

impl Default for WakeBook {
    fn default() -> Self {
        Self {
            devices: Devices::new(BTreeMap::new(), 0),
            own: OwnWake::default(),
            call_woken: None,
            texts: TextWakes::default(),
            due: Vec::new(),
        }
    }
}

impl WakeBook {
    /// Whether `signer` still needs a wake for `call_id`; marks it woken.
    fn mark_call(&mut self, call_id: &str, signer: &str) -> bool {
        if self.call_woken.as_ref().is_none_or(|(id, _)| id != call_id) {
            self.call_woken = Some((call_id.to_string(), BTreeSet::new()));
        }
        let (_, woken) = self.call_woken.as_mut().expect("set above");
        woken.insert(signer.to_string())
    }
}

impl PrivateDmSession {
    /// The tick's wake work: stamp who was heard, announce our own address,
    /// and queue wakes for a ringing call or waiting texts.
    pub(super) fn pump_wake(&mut self, now: u64, setup: &WakeSetup, lost_window: u64) {
        self.wake.devices.stamp(now);
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
        let next = self.wake.own.next(own, now);
        self.record_dirty |= next.key_replaced;
        let body = next.body;
        if self.wake.own.due(&body, epoch, ANNOUNCE_EVERY_MS).is_none() {
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
            self.wake.own.sent(body, epoch);
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
        self.wake.devices.heard(&signer);
        self.note_authenticated_frame("");
        let announcement: WakeAnnouncement = decode_json(&body)?;
        let withdrawn = announcement.wake_address.withdrawn();
        if let Some(changed) = self.wake.devices.accept(signer_hex, announcement) {
            self.record_dirty |= changed;
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
            .devices
            .reachable(setup)
            .filter(move |(signer, _)| !self.is_own_signer(signer))
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
            .filter(|(signer, _)| self.wake.devices.absent(signer, now, quiet))
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
    /// This device's wake address, announced in every chat, and the one
    /// service it wakes contacts through (api/wake.rs).
    pub(crate) fn set_wake(&mut self, setup: WakeSetup) {
        self.wake = setup;
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
            if session.wake.devices.forget(handle) {
                session.record_dirty = true;
                session.log_wake("wake service no longer knows a counterpart handle");
            }
        }
    }
}

#[cfg(test)]
#[path = "wake_tests.rs"]
pub(super) mod tests;
