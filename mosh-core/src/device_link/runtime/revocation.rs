use ed25519_dalek::{Signature, Signer};
use serde::{Deserialize, Serialize};

use super::*;
use crate::device_link::roster::{invalid, public_key};

const NOTICE_CONTEXT: &[u8] = crate::device_link::wire::ROSTER_NOTICE_PREFIX;

#[cfg(test)]
mod reload_tests;
#[cfg(test)]
mod tests;

#[derive(Serialize, Deserialize)]
struct RosterNotice {
    roster: DeviceRoster,
    sender: String,
    recipient: String,
    ack: bool,
    signature: String,
}

impl RosterNotice {
    fn bytes(&self) -> Result<Vec<u8>> {
        let mut bytes = NOTICE_CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(&self.roster, &self.sender, &self.recipient, self.ack))
                .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    fn seal(
        identity: &DeviceIdentity,
        recipient: &str,
        roster: DeviceRoster,
        ack: bool,
    ) -> Result<Vec<u8>> {
        let mut notice = Self {
            roster,
            sender: identity.device().device_id.clone(),
            recipient: recipient.into(),
            ack,
            signature: String::new(),
        };
        notice.signature = hex::encode(identity.key().sign(&notice.bytes()?).to_bytes());
        let mut bytes = NOTICE_CONTEXT.to_vec();
        bytes.extend(serde_json::to_vec(&notice).map_err(|_| invalid())?);
        if bytes.len() > 64 * 1024 {
            return Err(invalid());
        }
        Ok(bytes)
    }
}

impl DeviceLinkRuntime {
    /// Revoke one other installation; DM application continues durably in its runtime.
    pub fn revoke(&mut self, device_id: String) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        self.ensure_idle()?;
        let roster = self
            .identity
            .roster()
            .revoke(&device_id, &self.identity.key())?;
        let mut record = self.identity.record.clone();
        record.roster_delivery = self
            .identity
            .roster()
            .devices()?
            .into_iter()
            .filter(|d| d.device_id != self.identity.device().device_id)
            .collect();
        record.roster = roster;
        self.identity.update(record)?;
        self.roster_last_send = None;
        self.snapshot()
    }

    pub(super) fn retry_roster(&mut self) {
        if self
            .roster_last_send
            .is_some_and(|last| last.elapsed().as_millis() < 500)
            || self.identity.revoked().unwrap_or(true)
        {
            return;
        }
        for recipient in &self.identity.record.roster_delivery {
            if let Ok(packet) = RosterNotice::seal(
                &self.identity,
                &recipient.moss_peer_id,
                self.identity.roster().clone(),
                false,
            ) {
                let _ = self.transport.send(&recipient.moss_peer_id, &packet);
            }
        }
        self.roster_last_send = Some(Instant::now());
    }

    pub(super) fn receive_roster(&mut self, bytes: &[u8]) -> Result<bool> {
        let Some(bytes) = bytes.strip_prefix(NOTICE_CONTEXT) else {
            return Ok(false);
        };
        if bytes.len() > crate::device_link::wire::MAX_PACKET_BYTES {
            return Err(invalid());
        }
        let notice: RosterNotice = serde_json::from_slice(bytes).map_err(|_| invalid())?;
        if notice.recipient != self.identity.device().moss_peer_id {
            return Err(invalid());
        }
        let sender = notice
            .roster
            .known_device(&notice.sender)?
            .ok_or_else(invalid)?;
        let signature =
            Signature::from_slice(&hex::decode(&notice.signature).map_err(|_| invalid())?)
                .map_err(|_| invalid())?;
        public_key(&sender.signing_public_key)?
            .verify_strict(&notice.bytes()?, &signature)
            .map_err(|_| invalid())?;
        if notice.ack {
            if notice.roster.digest()? != self.identity.roster().digest()? {
                return Err(invalid());
            }
            let mut record = self.identity.record.clone();
            record
                .roster_delivery
                .retain(|d| d.device_id != sender.device_id);
            self.identity.update(record)?;
        } else {
            if !notice.roster.devices()?.contains(&sender) {
                return Err(invalid());
            }
            if notice.roster.digest()? != self.identity.roster().digest()? {
                self.identity.adopt_roster(notice.roster.clone())?;
            }
            self.reconcile_removal()?;
            let ack =
                RosterNotice::seal(&self.identity, &sender.moss_peer_id, notice.roster, true)?;
            let _ = self.transport.send(&sender.moss_peer_id, &ack);
        }
        Ok(true)
    }
}
