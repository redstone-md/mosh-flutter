//! Waking an iPhone through the wake service (mosh-wake), for every kind of
//! chat. iOS gives a closed app no process to listen with, so a device that
//! can only be reached through Apple's push service announces its wake
//! address inside each chat, sealed by MLS so only members read it and the
//! author's key signs it. A member with something for that device asks Dart
//! to send the service a wake. The announcement also carries the chat's
//! preview key, so a wake for texts can show them (`preview`). Old builds
//! drop the unknown control kind. Nothing here speaks HTTP.

pub mod preview;

use serde::{Deserialize, Serialize};

/// An unchanged announcement is repeated this often.
pub(crate) const ANNOUNCE_EVERY_MS: u64 = 6 * 60 * 60 * 1000;
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

    /// Whether `self`, about to be announced, differs enough from what
    /// was last announced and in which epoch.
    pub(crate) fn due_after(&self, sent: Option<&(Self, Option<u64>)>, epoch: Option<u64>) -> bool {
        sent.is_none_or(|(sent, at_epoch)| {
            sent.wake_address != self.wake_address
                || sent.preview_key != self.preview_key
                || *at_epoch != epoch
                || self.issued_at_ms.saturating_sub(sent.issued_at_ms) >= ANNOUNCE_EVERY_MS
        })
    }
}
