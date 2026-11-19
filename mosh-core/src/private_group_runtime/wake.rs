//! Waking members' iPhones for this device's texts in a group (see
//! conversation::wake). An iPhone announces its wake address and the
//! group's preview key in the group, as it does in a DM. A group has no
//! acknowledgements: a text counts as sent once it is in the room, and a
//! woken phone reads what it missed from the group's history. Nor is there a
//! keepalive, so an iPhone repeats its announcement every
//! [`PRESENT_EVERY_MS`] while Mosh runs; iOS suspends Mosh soon after it
//! leaves the screen, and the announcements stop. Once this device has sent,
//! it wakes each member device that announced an address and has sent no
//! authenticated frame for [`ABSENT_AFTER_MS`], for the texts sent since,
//! signed with this member's MLS key. The mesh is no sign of a phone: Moss
//! drops a peer only after a minute and a half of missed pings.

use super::*;
use crate::conversation::wake::preview::{
    seal, PreviewAuthor, PreviewChat, PreviewKeys, PreviewMember, TextWakes,
};
use crate::conversation::wake::{WakeAddress, WakeAnnouncement, WakeRequest, WakeSetup};
use crate::sender_auth::VerifiedSender;
use base64::{engine::general_purpose::STANDARD, Engine};
use std::collections::{BTreeMap, BTreeSet};

/// How often a device with a wake address repeats it in each group while
/// Mosh runs, as a DM's keepalive.
const PRESENT_EVERY_MS: u64 = 10_000;
/// A member device unheard this long is taken to be asleep: as long as a DM
/// takes to call its counterpart lost.
const ABSENT_AFTER_MS: u64 = 25_000;

/// What a group keeps of waking across restarts.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct GroupWakeRecord {
    /// Each member device's latest announcement, by its MLS signer.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    members: BTreeMap<String, WakeAnnouncement>,
    /// This device's preview keys for the group.
    #[serde(default, skip_serializing_if = "PreviewKeys::is_empty")]
    own_keys: PreviewKeys,
    /// The members the current key was made for: one of them leaving
    /// replaces it, so they cannot read what is sent after, even when they
    /// left while Mosh was closed.
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    keyed_for: BTreeSet<String>,
}

impl GroupWakeRecord {
    pub(super) fn is_empty(&self) -> bool {
        self == &Self::default()
    }
}

/// One group's wake bookkeeping; only `record` is persisted.
pub(super) struct GroupWakeBook {
    pub(super) record: GroupWakeRecord,
    announced: Option<(WakeAnnouncement, Option<u64>)>,
    heard: BTreeSet<String>,
    seen_at: HashMap<String, u64>,
    texts: HashMap<String, TextWakes>,
    /// When this run started: texts from before were not its to wake for,
    /// and a device not seen yet counts as seen then.
    since: u64,
    due: Vec<WakeRequest>,
    dirty: bool,
}

impl GroupWakeBook {
    pub(super) fn restore(record: GroupWakeRecord) -> Self {
        Self {
            record,
            announced: None,
            heard: BTreeSet::new(),
            seen_at: HashMap::new(),
            texts: HashMap::new(),
            since: now_ms(),
            due: Vec::new(),
            dirty: false,
        }
    }

    fn seen(&self, signer: &str) -> u64 {
        self.seen_at.get(signer).copied().unwrap_or(self.since)
    }

    /// The member devices to wake now, with what they announced.
    fn targets(&self, now: u64, setup: &WakeSetup) -> Vec<(String, WakeAnnouncement)> {
        self.record
            .members
            .iter()
            .filter(|(signer, held)| {
                setup.reaches(held) && now.saturating_sub(self.seen(signer)) >= ABSENT_AFTER_MS
            })
            .map(|(signer, held)| (signer.clone(), held.clone()))
            .collect()
    }

    /// Drops the devices of members who left, and replaces the key when
    /// one it was made for is gone.
    fn follow(&mut self, members: BTreeSet<String>, now: u64) {
        let record = &mut self.record;
        let before = record.members.len();
        record.members.retain(|signer, _| members.contains(signer));
        let mut changed = record.members.len() != before;
        if !record.own_keys.is_empty() {
            if !record.keyed_for.is_subset(&members) {
                record.own_keys.replace(now);
            }
            changed |= record.keyed_for != members;
            record.keyed_for = members;
        }
        self.dirty |= changed;
    }

    /// Stamps the devices heard since the last turn.
    fn note_heard(&mut self, now: u64) {
        for signer in std::mem::take(&mut self.heard) {
            self.texts.remove(&signer);
            self.seen_at.insert(signer, now);
        }
    }
}

/// One of this device's texts in the group.
struct OwnText {
    id: String,
    sent_at_ms: u64,
    body: String,
}

impl GroupSession {
    /// An authenticated frame from a member device: it is awake.
    pub(super) fn heard_member(&mut self, signer: &[u8]) {
        self.wake.heard.insert(hex::encode(signer));
    }

    /// One service turn's wake work: keep the key and the members current,
    /// announce this device's address, and wake absent members for texts.
    pub(super) fn pump_wake(&mut self, now: u64, setup: &WakeSetup) {
        if !self.joined || !self.crypto.is_ready() {
            return;
        }
        self.wake.note_heard(now);
        // Most groups have no iPhone in them: nothing to keep current.
        let record = &self.wake.record;
        if !record.own_keys.is_empty() || !record.members.is_empty() {
            let members = self.crypto.member_signers().into_iter().collect();
            self.wake.follow(members, now);
        }
        if let Some(address) = &setup.own {
            self.announce_wake(address, now);
        }
        self.wake_for_texts(now, setup);
    }

    fn announce_wake(&mut self, address: &WakeAddress, now: u64) {
        let preview_key = if address.withdrawn() {
            None
        } else {
            if self.wake.record.own_keys.rotate(now) {
                // A new key is made for the members there are now.
                self.wake.record.keyed_for = self.crypto.member_signers().into_iter().collect();
                self.wake.dirty = true;
            }
            self.wake.record.own_keys.current().map(str::to_string)
        };
        let body = WakeAnnouncement {
            wake_address: address.clone(),
            issued_at_ms: now,
            preview_key,
        };
        let epoch = self.crypto.epoch();
        let sent = self.wake.announced.as_ref();
        let changed = body.due_after(sent, epoch);
        let present =
            sent.is_some_and(|(sent, _)| now.saturating_sub(sent.issued_at_ms) < PRESENT_EVERY_MS);
        if !changed && present {
            return;
        }
        let Ok(wake_ciphertext_b64) = self.crypto.encrypt_json(&body) else {
            return;
        };
        let envelope = ControlEnvelope::WakeAddress {
            group_id: self.group_id.clone(),
            wake_ciphertext_b64,
        };
        if self.publish_control(&envelope).is_ok() {
            self.wake.announced = Some((body, epoch));
            if changed {
                self.log_wake("wake address announced");
            }
        }
    }

    /// A member device's announcement; its sender proof names the device.
    pub(super) fn accept_wake_address(
        &mut self,
        ciphertext_b64: &str,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let body = self.decrypt_application(ciphertext_b64, &sender)?;
        if sender.mls_signer == self.crypto.signer_public() {
            return Ok(());
        }
        let announcement: WakeAnnouncement = decode_json(&body)?;
        let signer = hex::encode(&sender.mls_signer);
        let held = self.wake.record.members.get(&signer);
        if !announcement.supersedes(held) {
            self.log_wake("member wake address stale or refused");
            return Ok(());
        }
        // Most are repeats that only say the device is awake.
        let changed = held.is_none_or(|held| {
            held.wake_address != announcement.wake_address
                || held.preview_key != announcement.preview_key
        });
        self.wake.record.members.insert(signer, announcement);
        if changed {
            self.wake.dirty = true;
            self.log_wake("member wake address kept");
        }
        Ok(())
    }

    fn wake_for_texts(&mut self, now: u64, setup: &WakeSetup) {
        let targets = self.wake.targets(now, setup);
        if targets.is_empty() {
            return;
        }
        let sent = self.own_texts();
        let sign = |bytes: &[u8]| self.crypto.sign_sender_proof(bytes).ok();
        let author = PreviewAuthor {
            chat: &self.group_id,
            key: self.crypto.signer_public(),
            sign: &sign,
        };
        for (signer, held) in targets {
            // What came before, the device took while it was awake.
            let seen = self.wake.seen(&signer);
            let waiting: BTreeSet<String> = sent
                .iter()
                .filter(|text| text.sent_at_ms > seen)
                .map(|text| text.id.clone())
                .collect();
            let wakes = self.wake.texts.entry(signer).or_default();
            if !wakes.due(&waiting, now) {
                continue;
            }
            let fresh = wakes.carry(waiting, now);
            let shown: Vec<String> = sent
                .iter()
                .filter(|text| fresh.contains(&text.id))
                .map(|text| text.body.clone())
                .collect();
            let preview = held
                .preview_key
                .as_deref()
                .and_then(|key| seal(key, &shown, Some(&author)));
            let request = held.wake_address.request(&self.group_id, None, preview);
            self.wake.due.push(request);
        }
    }

    /// The texts this device sent in this run, oldest first.
    fn own_texts(&self) -> Vec<OwnText> {
        let mut own: Vec<OwnText> = self
            .messages
            .iter()
            .rev()
            .filter(|message| message.from_fingerprint == self.device_fingerprint)
            .filter(|message| {
                matches!(
                    message.delivery_status,
                    Some(MessageDeliveryStatus::Sent | MessageDeliveryStatus::Delivered)
                ) && !message.is_service()
                    && !message.body.trim().is_empty()
            })
            .filter_map(|message| {
                let sent_at_ms = message.sent_at_ms.filter(|at| *at >= self.wake.since)?;
                Some(OwnText {
                    id: message.message_id.clone()?,
                    sent_at_ms,
                    body: message.body.clone(),
                })
            })
            .collect();
        own.sort_by_key(|text| text.sent_at_ms);
        own
    }

    fn log_wake(&self, line: &str) {
        dlog::write(LogLevel::Info, kinds::WAKE, &self.group_id, line);
    }

    fn preview_chat(&self) -> Option<PreviewChat> {
        let keys = &self.wake.record.own_keys;
        keys.current()?;
        let own = hex::encode(self.crypto.signer_public());
        let mut members: Vec<PreviewMember> = self
            .crypto
            .member_signers()
            .into_iter()
            .filter(|signer| *signer != own)
            .filter_map(|signer| {
                let key = hex::decode(signer).ok()?;
                Some(PreviewMember {
                    name: self.member_name(&key)?,
                    key: STANDARD.encode(key),
                })
            })
            .collect();
        members.sort();
        Some(PreviewChat {
            chat_id: self.group_id.clone(),
            name: self.label.clone().unwrap_or_default(),
            keys: keys.opening(),
            members: Some(members),
        })
    }

    /// The name a member goes by in the group, by their MLS key: the name
    /// in their MLS credential, or, in an org group, where that is their
    /// peer id, the name their frames carry.
    fn member_name(&self, signer: &[u8]) -> Option<String> {
        let identity = self.crypto.member_identity_for_signer(signer)?;
        if self.org_pubkey.is_none() {
            return Some(identity);
        }
        self.member_names.get(&identity).cloned().or_else(|| {
            self.messages
                .iter()
                .rev()
                .find(|message| message.from_fingerprint == identity)
                .map(|message| message.from_device.clone())
        })
    }
}

#[path = "wake_runtime.rs"]
mod runtime;

#[cfg(test)]
#[path = "wake_tests.rs"]
mod tests;
