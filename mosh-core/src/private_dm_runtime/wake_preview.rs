//! Waking a phone for texts, with previews of them. The phone gives every chat its own
//! preview key and announces it with its wake address; a contact seals the
//! texts a wake stands for under that key, and the phone's notification
//! extension opens them with the keys the app left it. Which key opens a
//! preview tells the extension which chat it came from, so one contact
//! cannot pass a preview off as another's. The wake service and Apple carry
//! only the sealed bytes.

use super::*;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// A chat wakes a phone for new texts at most this often; texts sent closer
/// together share one notification.
pub(super) const MESSAGE_WAKE_GAP_MS: u64 = 10_000;
/// A chat's preview key is replaced this often; the one before stays open
/// for previews already on their way.
const KEY_LIFETIME_MS: u64 = 24 * 60 * 60 * 1000;
/// The longest sealed preview, in base64url characters: APNs takes 4 KB a
/// push, and the alert around the preview needs about a hundred bytes. The
/// wake service refuses a longer one.
pub(crate) const PREVIEW_MAX_LEN: usize = 3_800;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
/// The longest plaintext that still seals within [`PREVIEW_MAX_LEN`].
const PLAINTEXT_MAX: usize = PREVIEW_MAX_LEN * 3 / 4 - NONCE_LEN - TAG_LEN;

/// This device's preview keys for one chat, kept with the session record.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct PreviewKeys {
    current: Option<PreviewKey>,
    previous: Option<PreviewKey>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct PreviewKey {
    /// 32 bytes for AES-256-GCM, in standard base64.
    key: String,
    issued_at_ms: u64,
}

impl PreviewKeys {
    /// Makes a new current key when there is none or it is a day old; true
    /// when it did, so the record is saved.
    pub(super) fn rotate(&mut self, now: u64) -> bool {
        let fresh = self
            .current
            .as_ref()
            .is_some_and(|held| now.saturating_sub(held.issued_at_ms) < KEY_LIFETIME_MS);
        if fresh {
            return false;
        }
        let mut key = [0u8; 32];
        OsRng.fill_bytes(&mut key);
        self.previous = self.current.take();
        self.current = Some(PreviewKey {
            key: STANDARD.encode(key),
            issued_at_ms: now,
        });
        true
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.current.is_none()
    }

    /// The key contacts seal with now.
    pub(super) fn current(&self) -> Option<&str> {
        self.current.as_ref().map(|held| held.key.as_str())
    }

    /// Every key a preview may still arrive under, newest first.
    fn opening(&self) -> Vec<String> {
        [&self.current, &self.previous]
            .into_iter()
            .flatten()
            .map(|held| held.key.clone())
            .collect()
    }
}

/// Which of a chat's texts its wakes carried, so each wake carries only
/// the new ones.
#[derive(Default)]
pub(super) struct TextWakes {
    at: u64,
    carried: BTreeSet<String>,
    /// What the last wake carried first; a refusal makes it new again.
    last: BTreeSet<String>,
}

impl TextWakes {
    /// Whether `waiting` holds a text no wake carried, once the chat may
    /// wake the phone again.
    fn due(&self, waiting: &BTreeSet<String>, now: u64) -> bool {
        !waiting.is_subset(&self.carried)
            && (self.at == 0 || now.saturating_sub(self.at) >= MESSAGE_WAKE_GAP_MS)
    }

    /// Marks `waiting` carried by a wake now; returns the texts new to it.
    fn carry(&mut self, waiting: BTreeSet<String>, now: u64) -> BTreeSet<String> {
        self.last = waiting.difference(&self.carried).cloned().collect();
        self.carried = waiting;
        self.at = now;
        self.last.clone()
    }

    /// The last wake was refused: what it carried first is new again.
    fn give_back(&mut self) {
        let last = std::mem::take(&mut self.last);
        self.carried.retain(|id| !last.contains(id));
    }
}

/// A key as announced: 32 bytes in standard base64.
pub(super) fn valid_key(key: &str) -> Option<[u8; 32]> {
    STANDARD.decode(key).ok()?.try_into().ok()
}

/// Seals `texts` under a counterpart's preview key: base64url of nonce,
/// ciphertext and tag (CryptoKit's `AES.GCM.SealedBox.combined`) over
/// `{"text": …}`. None for a key that does not read or nothing to show.
pub(super) fn seal(key: &str, texts: &[String]) -> Option<String> {
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce);
    seal_with(key, texts, nonce)
}

fn seal_with(key: &str, texts: &[String], nonce: [u8; NONCE_LEN]) -> Option<String> {
    let cipher = Aes256Gcm::new_from_slice(&valid_key(key)?).ok()?;
    let text = texts
        .iter()
        .map(|text| text.trim())
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    if text.is_empty() {
        return None;
    }
    let sealed = cipher
        .encrypt(Nonce::from_slice(&nonce), fit(text).as_bytes())
        .ok()?;
    Some(URL_SAFE_NO_PAD.encode([&nonce[..], &sealed].concat()))
}

/// `{"text": …}` within [`PLAINTEXT_MAX`] bytes, the text cut at a
/// character and ended with "…" when it is longer.
fn fit(mut text: String) -> String {
    loop {
        let body = serde_json::json!({ "text": text }).to_string();
        let over = body.len().saturating_sub(PLAINTEXT_MAX);
        if over == 0 {
            return body;
        }
        // Escapes make the JSON longer than the text, so the cut is in
        // proportion to it; the loop takes what one cut leaves over.
        let cut = (over * text.len()).div_ceil(body.len()).max(1);
        let mut end = text.len().saturating_sub(cut + '…'.len_utf8());
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        text.truncate(end);
        text.push('…');
    }
}

/// What this iPhone's notification extension needs for one chat: the name
/// the user sees for it and every key a preview may arrive under.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreviewChat {
    pub session_id: String,
    pub name: String,
    pub keys: Vec<String>,
}

impl PrivateDmSession {
    /// Wakes an absent counterpart for texts it has not acknowledged: queued
    /// ones, and ones sent while it still looked connected (a phone that just
    /// went to sleep stays Connected for the lost window). Each wake carries
    /// the texts no wake carried before, sealed for the device it goes to.
    pub(super) fn wake_for_messages(&mut self, now: u64, lost_window: u64, service: Option<&str>) {
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
        if waiting.is_empty() || !self.wake.texts.due(&waiting, now) {
            return;
        }
        let targets = self.wake_targets(now, lost_window, service);
        if targets.is_empty() {
            return;
        }
        let fresh = self.wake.texts.carry(waiting, now);
        let texts = self.texts_of(&fresh);
        self.log_wake("wake requested for unacknowledged texts");
        for (_, held) in targets {
            let preview = held
                .preview_key
                .as_deref()
                .and_then(|key| seal(key, &texts));
            self.wake.due.push(held.wake_address.request(None, preview));
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
    /// The service refused a texts wake to `handle` for good: the texts it
    /// carried first go with the next wake.
    pub fn wake_refused(&mut self, handle: &str) {
        for session in self.sessions.values_mut() {
            let wake = &mut session.wake;
            if wake
                .peers
                .values()
                .any(|held| held.wake_address.handle == handle)
            {
                wake.texts.give_back();
            }
        }
    }

    /// The chats this device announced a preview key in; the API names them
    /// as the user does.
    pub fn preview_chats(&self) -> Vec<PreviewChat> {
        self.sessions
            .values()
            .filter(|session| session.wake.own_keys.current().is_some())
            .map(|session| PreviewChat {
                session_id: session.session_id.clone(),
                name: session.peer_display_name.clone().unwrap_or_default(),
                keys: session.wake.own_keys.opening(),
            })
            .collect()
    }
}

#[cfg(test)]
#[path = "wake_preview_tests.rs"]
mod tests;
