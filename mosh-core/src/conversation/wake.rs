//! Waking an iPhone through the wake service (mosh-wake), for every kind of
//! chat. iOS gives a closed app no process to listen with, so a device that
//! can only be reached through Apple's push service announces its wake
//! address inside each chat, sealed by MLS so only members read it and the
//! author's key signs it. A member with something for that device asks Dart
//! to send the service a wake. The announcement also carries the chat's
//! preview key, so a wake for texts can show them (`preview`). Old builds
//! drop the unknown control kind. Nothing here speaks HTTP.

pub mod preview;

use preview::PreviewKeys;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// The service's handles are 32 random bytes in unpadded base64url.
const HANDLE_LEN: usize = 43;
pub(crate) const SERVICE_MAX_LEN: usize = 200;

/// Where a device can be woken: its wake service and the handle the service
/// gave it. An empty handle withdraws an earlier announcement.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WakeAddress {
    pub service: String,
    pub handle: String,
}

impl WakeAddress {
    pub(crate) fn withdrawn(&self) -> bool {
        self.handle.is_empty()
    }

    pub(crate) fn request(
        &self,
        chat: &str,
        call_id: Option<String>,
        preview: Option<String>,
    ) -> WakeRequest {
        WakeRequest {
            service: self.service.clone(),
            handle: self.handle.clone(),
            chat: chat.to_string(),
            call_id,
            preview,
        }
    }

    /// A member's address becomes an HTTP request on this device, so only a
    /// bounded https URL and a handle of the service's shape pass.
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

/// What this installation knows of waking: its own address, announced in
/// every chat, and the one service it wakes others through, the build's
/// own. A member names its service, so any other one would let a member
/// point this device's requests anywhere; without one nobody is woken.
#[derive(Debug, Clone, Default)]
pub(crate) struct WakeSetup {
    pub(crate) own: Option<WakeAddress>,
    pub(crate) service: Option<String>,
}

impl WakeSetup {
    /// Whether `held` names a live address on this build's service.
    pub(crate) fn reaches(&self, held: &WakeAnnouncement) -> bool {
        !held.wake_address.withdrawn()
            && Some(held.wake_address.service.as_str()) == self.service.as_deref()
    }
}

/// One wake for Dart to send: `chat` is the conversation it is for,
/// `call_id` names a ringing call, none means texts are waiting; `preview`
/// is those texts, sealed for the phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WakeRequest {
    pub service: String,
    pub handle: String,
    pub chat: String,
    pub call_id: Option<String>,
    pub preview: Option<String>,
}

/// The frame body. Its field names keep it from reading as any other body.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct WakeAnnouncement {
    pub(crate) wake_address: WakeAddress,
    pub(crate) issued_at_ms: u64,
    /// What a wake's texts are sealed with for this chat; absent in builds
    /// before previews and in a withdrawal.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) preview_key: Option<String>,
}

impl WakeAnnouncement {
    /// Whether this replaces `held`: it is newer, and its address and key
    /// are ones this device may use.
    pub(crate) fn supersedes(&self, held: Option<&Self>) -> bool {
        held.is_none_or(|held| self.issued_at_ms > held.issued_at_ms)
            && self.wake_address.valid()
            && self
                .preview_key
                .as_deref()
                .is_none_or(|key| preview::valid_key(key).is_some())
    }
}

/// The other devices of a chat that can be woken: what each announced, by
/// its MLS signer, and when each was last heard. Only `announced` is kept
/// across restarts.
pub(crate) struct Devices {
    pub(crate) announced: BTreeMap<String, WakeAnnouncement>,
    heard: BTreeSet<String>,
    heard_at: HashMap<String, u64>,
    /// When a device not heard yet counts as heard last.
    unheard: u64,
}

impl Devices {
    pub(crate) fn new(announced: BTreeMap<String, WakeAnnouncement>, unheard: u64) -> Self {
        Self {
            announced,
            heard: BTreeSet::new(),
            heard_at: HashMap::new(),
            unheard,
        }
    }

    /// Keeps `announcement` when it is valid and newer than the one held:
    /// Some(true) when its address or key differ, Some(false) for a repeat,
    /// None when refused.
    pub(crate) fn accept(
        &mut self,
        signer: String,
        announcement: WakeAnnouncement,
    ) -> Option<bool> {
        let held = self.announced.get(&signer);
        if !announcement.supersedes(held) {
            return None;
        }
        let changed = held.is_none_or(|held| {
            held.wake_address != announcement.wake_address
                || held.preview_key != announcement.preview_key
        });
        self.announced.insert(signer, announcement);
        Some(changed)
    }

    /// An authenticated frame from `signer` arrived; the next turn stamps it.
    pub(crate) fn heard(&mut self, signer: &[u8]) {
        self.heard.insert(hex::encode(signer));
    }

    /// Stamps the devices heard since the last turn and returns them.
    pub(crate) fn stamp(&mut self, now: u64) -> Vec<String> {
        let heard: Vec<String> = std::mem::take(&mut self.heard).into_iter().collect();
        for signer in &heard {
            self.heard_at.insert(signer.clone(), now);
        }
        heard
    }

    pub(crate) fn last_heard(&self, signer: &str) -> u64 {
        self.heard_at.get(signer).copied().unwrap_or(self.unheard)
    }

    pub(crate) fn absent(&self, signer: &str, now: u64, quiet: u64) -> bool {
        now.saturating_sub(self.last_heard(signer)) >= quiet
    }

    /// The devices with a live address on this build's service.
    pub(crate) fn reachable<'a>(
        &'a self,
        setup: &'a WakeSetup,
    ) -> impl Iterator<Item = (&'a String, &'a WakeAnnouncement)> + 'a {
        self.announced
            .iter()
            .filter(move |(_, held)| setup.reaches(held))
    }

    /// The devices that announced `handle`.
    pub(crate) fn with_handle<'a>(&'a self, handle: &'a str) -> impl Iterator<Item = &'a String> {
        self.announced
            .iter()
            .filter(move |(_, held)| held.wake_address.handle == handle)
            .map(|(signer, _)| signer)
    }

    /// Drops every announcement of `handle`; true when one was held.
    pub(crate) fn forget(&mut self, handle: &str) -> bool {
        self.retain(|_, held| held.wake_address.handle != handle)
    }

    /// Drops the devices of those no longer in the chat; true when any.
    pub(crate) fn keep_members(&mut self, members: &BTreeSet<String>) -> bool {
        self.retain(|signer, _| members.contains(signer))
    }

    fn retain(&mut self, keep: impl FnMut(&String, &mut WakeAnnouncement) -> bool) -> bool {
        let before = self.announced.len();
        self.announced.retain(keep);
        self.announced.len() != before
    }
}

/// This device's own announcement in one chat: its preview keys, kept
/// across restarts, and what it last sent and in which epoch.
#[derive(Default)]
pub(crate) struct OwnWake {
    pub(crate) keys: PreviewKeys,
    sent: Option<(WakeAnnouncement, Option<u64>)>,
}

/// An announcement ready to send, and whether making it replaced the key.
pub(crate) struct NextAnnouncement {
    pub(crate) body: WakeAnnouncement,
    pub(crate) key_replaced: bool,
}

impl OwnWake {
    pub(crate) fn new(keys: PreviewKeys) -> Self {
        Self { keys, sent: None }
    }

    /// What to announce for `address` now, with a key no older than a day;
    /// a withdrawal carries none. Always newer than what was sent, or a
    /// change in the same millisecond would read as stale to members.
    pub(crate) fn next(&mut self, address: &WakeAddress, now: u64) -> NextAnnouncement {
        let issued_at_ms = self
            .sent
            .as_ref()
            .map_or(now, |(sent, _)| now.max(sent.issued_at_ms + 1));
        let key_replaced = !address.withdrawn() && self.keys.rotate(now);
        let preview_key = if address.withdrawn() {
            None
        } else {
            self.keys.current().map(str::to_string)
        };
        NextAnnouncement {
            body: WakeAnnouncement {
                wake_address: address.clone(),
                issued_at_ms,
                preview_key,
            },
            key_replaced,
        }
    }

    /// Whether `body` goes out in `epoch`: Some(true) when it differs from
    /// what was sent or the epoch moved, Some(false) for a repeat once
    /// `every` has passed, None when not due.
    pub(crate) fn due(
        &self,
        body: &WakeAnnouncement,
        epoch: Option<u64>,
        every: u64,
    ) -> Option<bool> {
        let Some((sent, at_epoch)) = &self.sent else {
            return Some(true);
        };
        let changed = sent.wake_address != body.wake_address
            || sent.preview_key != body.preview_key
            || *at_epoch != epoch;
        let repeat = body.issued_at_ms.saturating_sub(sent.issued_at_ms) >= every;
        (changed || repeat).then_some(changed)
    }

    pub(crate) fn sent(&mut self, body: WakeAnnouncement, epoch: Option<u64>) {
        self.sent = Some((body, epoch));
    }

    /// The other side may have missed it: announce again on the next turn.
    pub(crate) fn resend(&mut self) {
        self.sent = None;
    }
}

#[cfg(test)]
impl WakeSetup {
    /// A device that announces `address` and wakes nobody.
    pub(crate) fn announcing(address: WakeAddress) -> Self {
        Self {
            own: Some(address),
            service: None,
        }
    }

    /// A device that wakes others through `service`.
    pub(crate) fn waking_through(service: &str) -> Self {
        Self {
            own: None,
            service: Some(service.to_string()),
        }
    }
}

#[cfg(test)]
#[path = "wake_tests.rs"]
pub(crate) mod tests;
