//! Previews of the texts a wake stands for. The phone gives every chat its
//! own preview key and announces it with its wake address; a member seals
//! the texts under that key, and the phone's notification extension opens
//! them with the keys the app left it. Which key opens a preview tells the
//! extension which chat it came from, so a contact cannot pass a preview off
//! as another chat's. Every member of a group knows its key, so a group
//! preview also carries its author's MLS signature, by which the extension
//! finds the author among the members the app left it. The wake service and Apple
//! carry only the sealed bytes.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// A chat wakes a device for new texts at most this often; texts sent
/// closer together share one notification.
pub(crate) const MESSAGE_WAKE_GAP_MS: u64 = 10_000;
/// A chat's preview key is replaced this often; the one before stays open
/// for previews already on their way.
pub(crate) const KEY_LIFETIME_MS: u64 = 24 * 60 * 60 * 1000;
/// The longest sealed preview, in base64url characters: APNs takes 4 KB a
/// push, and the alert around the preview needs about a hundred bytes. The
/// wake service refuses a longer one.
pub(crate) const PREVIEW_MAX_LEN: usize = 3_800;
pub(crate) const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
/// The longest plaintext that still seals within [`PREVIEW_MAX_LEN`].
const PLAINTEXT_MAX: usize = PREVIEW_MAX_LEN * 3 / 4 - NONCE_LEN - TAG_LEN;
/// Names what a group preview's signature is over, so it signs nothing else.
const SIGNED_AS: &str = "mosh-group-preview-v1";

/// This device's preview keys for one chat, kept with the chat's record.
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
    pub(crate) fn rotate(&mut self, now: u64) -> bool {
        let fresh = self
            .current
            .as_ref()
            .is_some_and(|held| now.saturating_sub(held.issued_at_ms) < KEY_LIFETIME_MS);
        if !fresh {
            self.replace(now);
        }
        !fresh
    }

    /// Makes a new current key now, keeping the one before.
    pub(crate) fn replace(&mut self, now: u64) {
        let mut key = [0u8; 32];
        OsRng.fill_bytes(&mut key);
        self.previous = self.current.take();
        self.current = Some(PreviewKey {
            key: STANDARD.encode(key),
            issued_at_ms: now,
        });
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.current.is_none()
    }

    /// The key members seal with now.
    pub(crate) fn current(&self) -> Option<&str> {
        self.current.as_ref().map(|held| held.key.as_str())
    }

    /// Every key a preview may still arrive under, newest first.
    pub(crate) fn opening(&self) -> Vec<String> {
        [&self.current, &self.previous]
            .into_iter()
            .flatten()
            .map(|held| held.key.clone())
            .collect()
    }
}

/// Which texts the wakes to one device carried, so each wake carries only
/// the new ones.
#[derive(Default)]
pub(crate) struct TextWakes {
    at: u64,
    carried: BTreeSet<String>,
    /// What the last wake carried first; a refusal makes it new again.
    last: BTreeSet<String>,
}

impl TextWakes {
    /// Whether `waiting` holds a text no wake carried, once the device may
    /// be woken again.
    pub(crate) fn due(&self, waiting: &BTreeSet<String>, now: u64) -> bool {
        !waiting.is_subset(&self.carried)
            && (self.at == 0 || now.saturating_sub(self.at) >= MESSAGE_WAKE_GAP_MS)
    }

    /// Marks `waiting` carried by a wake now; returns the texts new to it.
    pub(crate) fn carry(&mut self, waiting: BTreeSet<String>, now: u64) -> BTreeSet<String> {
        self.last = waiting.difference(&self.carried).cloned().collect();
        self.carried = waiting;
        self.at = now;
        self.last.clone()
    }

    /// The last wake was refused: what it carried first is new again.
    pub(crate) fn give_back(&mut self) {
        let last = std::mem::take(&mut self.last);
        self.carried.retain(|id| !last.contains(id));
    }
}

/// The member who wrote a group preview, and what signs as them: their
/// MLS leaf key, whose public half is `key`. The phone names the author by
/// that key, never by a name the preview claims.
pub(crate) struct PreviewAuthor<'a> {
    pub(crate) chat: &'a str,
    pub(crate) key: Vec<u8>,
    pub(crate) sign: &'a dyn Fn(&[u8]) -> Option<Vec<u8>>,
}

impl PreviewAuthor<'_> {
    /// `{"text", "from", "sig"}`: the signature covers the chat and the
    /// text, each length-prefixed, so neither can be moved into the other.
    fn body(&self, text: &str) -> Option<String> {
        let signed = (self.sign)(&signing_input(&[SIGNED_AS, self.chat, text]))?;
        Some(
            serde_json::json!({
                "text": text,
                "from": STANDARD.encode(&self.key),
                "sig": STANDARD.encode(signed),
            })
            .to_string(),
        )
    }
}

/// Each part as a 4-byte big-endian length and its UTF-8 bytes.
fn signing_input(parts: &[&str]) -> Vec<u8> {
    parts
        .iter()
        .flat_map(|part| {
            let length = u32::try_from(part.len()).unwrap_or(u32::MAX);
            length.to_be_bytes().into_iter().chain(part.bytes())
        })
        .collect()
}

/// A key as announced: 32 bytes in standard base64.
pub(crate) fn valid_key(key: &str) -> Option<[u8; 32]> {
    STANDARD.decode(key).ok()?.try_into().ok()
}

/// Seals `texts` under a member's preview key: base64url of nonce,
/// ciphertext and tag (CryptoKit's `AES.GCM.SealedBox.combined`) over
/// `{"text": …}`, or the signed group body when `author` is given. None
/// for a key that does not read or nothing to show.
pub(crate) fn seal(key: &str, texts: &[String], author: Option<&PreviewAuthor>) -> Option<String> {
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce);
    seal_with(key, texts, author, nonce)
}

pub(crate) fn seal_with(
    key: &str,
    texts: &[String],
    author: Option<&PreviewAuthor>,
    nonce: [u8; NONCE_LEN],
) -> Option<String> {
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
    let body = fit(text, |text| match author {
        Some(author) => author.body(text),
        None => Some(serde_json::json!({ "text": text }).to_string()),
    })?;
    let sealed = cipher
        .encrypt(Nonce::from_slice(&nonce), body.as_bytes())
        .ok()?;
    Some(URL_SAFE_NO_PAD.encode([&nonce[..], &sealed].concat()))
}

/// The body `make` gives for `text`, within [`PLAINTEXT_MAX`] bytes: the
/// text cut at a character and ended with "…" when it is longer. None when
/// even an empty text does not fit.
fn fit(mut text: String, make: impl Fn(&str) -> Option<String>) -> Option<String> {
    loop {
        let body = make(&text)?;
        let over = body.len().saturating_sub(PLAINTEXT_MAX);
        if over == 0 {
            return Some(body);
        }
        if text.len() <= '…'.len_utf8() {
            return None;
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
/// the user sees for it, every key a preview may arrive under and, for a
/// group, the other members whose signed previews it shows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreviewChat {
    pub chat_id: String,
    pub name: String,
    pub keys: Vec<String>,
    pub members: Option<Vec<PreviewMember>>,
}

/// A group member as the extension names them: their MLS key, in standard
/// base64, and their name in the group.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct PreviewMember {
    pub key: String,
    pub name: String,
}

/// A group preview's text and the key that signed it, when `key` opens
/// it and its signature holds for `chat`.
#[cfg(test)]
pub(crate) fn open_signed(key: &str, preview: &str, chat: &str) -> Option<(String, Vec<u8>)> {
    use ed25519_dalek::{Signature, Verifier, VerifyingKey};
    let sealed = URL_SAFE_NO_PAD.decode(preview).ok()?;
    let (nonce, body) = sealed.split_at(NONCE_LEN);
    let plain = Aes256Gcm::new_from_slice(&valid_key(key)?)
        .ok()?
        .decrypt(Nonce::from_slice(nonce), body)
        .ok()?;
    let body: serde_json::Value = serde_json::from_slice(&plain).ok()?;
    let [text, from, sig] =
        ["text", "from", "sig"].map(|field| body[field].as_str().unwrap_or_default());
    let from = STANDARD.decode(from).ok()?;
    let sig = Signature::from_slice(&STANDARD.decode(sig).ok()?).ok()?;
    VerifyingKey::from_bytes(&from.clone().try_into().ok()?)
        .ok()?
        .verify(&signing_input(&[SIGNED_AS, chat, text]), &sig)
        .ok()?;
    Some((text.to_string(), from))
}

#[cfg(test)]
#[path = "preview_tests.rs"]
mod tests;
