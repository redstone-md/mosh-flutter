//! Waking a counterpart's iPhone through the wake service (mosh-wake). A
//! device that can only be reached through Apple's push service announces its
//! wake address inside the chat; a device that has a call ringing or texts
//! it has not acknowledged while it is away asks Dart to send the service a wake. The
//! address rides an MLS application message, so the author's MLS key signs it
//! and only members of the chat can read it. Old builds drop the unknown
//! control kind. Nothing here speaks HTTP.

use super::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// An unchanged announcement is repeated this often.
const ANNOUNCE_EVERY_MS: u64 = 6 * 60 * 60 * 1000;
/// A call wakes a device not heard for a keepalive and a little more: the
/// lost window would leave the woken phone seconds of a 30-second ring.
/// Waking one that was only slow costs a second ring of the same call.
const CALL_QUIET_MS: u64 = KEEPALIVE_MS + 2_000;
/// The service wakes a phone for messages at most once a minute.
const MESSAGE_WAKE_GAP_MS: u64 = 60_000;
/// The service's handles are 32 random bytes in unpadded base64url.
const HANDLE_LEN: usize = 43;
const SERVICE_MAX_LEN: usize = 200;

/// Where a device can be woken: its wake service and the handle the service
/// gave it. An empty handle withdraws an earlier announcement.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WakeAddress {
    pub service: String,
    pub handle: String,
}

impl WakeAddress {
    fn withdrawn(&self) -> bool {
        self.handle.is_empty()
    }

    fn request(self, call_id: Option<String>) -> WakeRequest {
        WakeRequest {
            service: self.service,
            handle: self.handle,
            call_id,
        }
    }

    /// A counterpart's address becomes an HTTP request on this device, so
    /// only a bounded https URL and a handle of the service's shape pass.
    fn valid(&self) -> bool {
        let handle = self.handle.len() == HANDLE_LEN
            && self
                .handle
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_');
        let service = self.service.len() <= SERVICE_MAX_LEN
            && self.service.starts_with("https://")
            && self.service.bytes().all(|byte| byte.is_ascii_graphic());
        self.withdrawn() || (handle && service)
    }
}

/// One wake for Dart to send: `call_id` names the ringing call, none means
/// texts are waiting.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WakeRequest {
    pub service: String,
    pub handle: String,
    pub call_id: Option<String>,
}

/// The frame body. Its field names keep it from reading as any other body.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct WakeAnnouncement {
    wake_address: WakeAddress,
    issued_at_ms: u64,
}

/// One session's wake bookkeeping. Only `peers` is persisted.
#[derive(Default)]
pub(super) struct WakeBook {
    /// Each counterpart device's latest announcement, by its MLS signer.
    pub(super) peers: BTreeMap<String, WakeAnnouncement>,
    /// What this device last announced, in which epoch, when. Cleared when
    /// the counterpart connects, so it hears the address again.
    pub(super) announced: Option<(WakeAddress, Option<u64>, u64)>,
    heard_since_tick: BTreeSet<String>,
    heard_at: HashMap<String, u64>,
    call_woken: Option<(String, BTreeSet<String>)>,
    message_woken: (u64, BTreeSet<String>),
    due: Vec<WakeRequest>,
}

impl WakeBook {
    /// Keeps `announcement` when it is valid and newer than the one held.
    pub(super) fn accept(&mut self, signer: String, announcement: WakeAnnouncement) -> bool {
        let newer = self
            .peers
            .get(&signer)
            .is_none_or(|held| announcement.issued_at_ms > held.issued_at_ms);
        if !newer || !announcement.wake_address.valid() {
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

    fn announce_due(&self, own: &WakeAddress, epoch: Option<u64>, now: u64) -> bool {
        self.announced
            .as_ref()
            .is_none_or(|(address, at_epoch, at)| {
                address != own || *at_epoch != epoch || now.saturating_sub(*at) >= ANNOUNCE_EVERY_MS
            })
    }

    /// Whether `signer` still needs a wake for `call_id`; marks it woken.
    fn mark_call(&mut self, call_id: &str, signer: &str) -> bool {
        if self.call_woken.as_ref().is_none_or(|(id, _)| id != call_id) {
            self.call_woken = Some((call_id.to_string(), BTreeSet::new()));
        }
        let (_, woken) = self.call_woken.as_mut().expect("set above");
        woken.insert(signer.to_string())
    }

    /// Texts no wake has gone out for, once the service would take another.
    fn messages_due(&self, waiting: &BTreeSet<String>, now: u64) -> bool {
        let (at, woken) = &self.message_woken;
        !waiting.is_subset(woken) && (*at == 0 || now.saturating_sub(*at) >= MESSAGE_WAKE_GAP_MS)
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
    pub(super) fn pump_wake(&mut self, now: u64, own: Option<&WakeAddress>, lost_window: u64) {
        self.wake.stamp(now);
        if let Some(own) = own {
            self.announce_wake(own, now);
        }
        self.wake_for_call(now);
        self.wake_for_messages(now, lost_window);
    }

    fn announce_wake(&mut self, own: &WakeAddress, now: u64) {
        let epoch = self.crypto.epoch();
        if self.state != DmSessionState::Connected
            || !self.can_encrypt_for_peer()
            || !self.wake.announce_due(own, epoch, now)
        {
            return;
        }
        let body = WakeAnnouncement {
            wake_address: own.clone(),
            issued_at_ms: now,
        };
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
            self.wake.announced = Some((own.clone(), epoch, now));
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

    fn log_wake(&self, line: &str) {
        dlog::write(LogLevel::Info, kinds::WAKE, &self.session_id, line);
    }

    fn is_own_signer(&self, signer: &str) -> bool {
        *signer == hex::encode(self.crypto.signer_public())
            || self
                .membership
                .as_ref()
                .is_some_and(|membership| membership.call_own(signer))
    }

    /// Whether some counterpart device that is not connected can be woken,
    /// so a call may ring it.
    pub(super) fn can_wake_counterpart(&self) -> bool {
        self.peer_joined
            && self.crypto.is_ready()
            && self
                .wake
                .peers
                .iter()
                .any(|(signer, held)| !held.wake_address.withdrawn() && !self.is_own_signer(signer))
    }

    /// Counterpart devices with a live address not heard for `quiet`.
    fn wake_targets(&self, now: u64, quiet: u64) -> Vec<(String, WakeAddress)> {
        self.wake
            .peers
            .iter()
            .filter(|(signer, held)| {
                !held.wake_address.withdrawn()
                    && !self.is_own_signer(signer)
                    && self.wake.absent(signer, now, quiet)
            })
            .map(|(signer, held)| (signer.clone(), held.wake_address.clone()))
            .collect()
    }

    fn wake_for_call(&mut self, now: u64) {
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
        for (signer, address) in self.wake_targets(now, CALL_QUIET_MS) {
            if self.wake.mark_call(&call_id, &signer) {
                self.wake.due.push(address.request(Some(call_id.clone())));
                self.log_wake(&format!("wake requested for call {call_id}"));
            }
        }
    }

    /// Wakes an absent counterpart for texts it has not acknowledged: queued
    /// ones, and ones sent while it still looked connected (a phone that just
    /// went to sleep stays Connected for the lost window).
    fn wake_for_messages(&mut self, now: u64, lost_window: u64) {
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
        if waiting.is_empty() || !self.wake.messages_due(&waiting, now) {
            return;
        }
        let targets = self.wake_targets(now, lost_window);
        if targets.is_empty() {
            return;
        }
        self.wake.message_woken = (now, waiting);
        self.log_wake("wake requested for unacknowledged texts");
        for (_, address) in targets {
            self.wake.due.push(address.request(None));
        }
    }
}

impl PrivateDmRuntime {
    /// This device's wake address, announced in every chat. An empty handle
    /// withdraws it; never calling this announces nothing.
    pub fn set_wake_address(&mut self, address: WakeAddress) {
        let line = if address.withdrawn() {
            "wake address withdrawn"
        } else {
            "wake address set"
        };
        dlog::write(LogLevel::Info, kinds::WAKE, KIND, line);
        self.own_wake = Some(address);
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
mod tests;
