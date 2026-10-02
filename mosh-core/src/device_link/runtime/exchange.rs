use super::*;
use crate::device_link::{roster::invalid, wire};

pub(super) struct Exchange {
    pub(super) qr: PairingQr,
    pub(super) joining: Option<DeviceDescriptor>,
    pub(super) role: Role,
    pub(super) trusted: Option<DeviceDescriptor>,
    pub(super) base: Option<DeviceRoster>,
    pub(super) packet: Option<Vec<u8>>,
    pub(super) last_send: Option<Instant>,
    pub(super) last_response: Instant,
}

impl Exchange {
    pub(super) fn awaits_adopted_approval(&self, identity: &DeviceIdentity) -> bool {
        identity.record.pending.as_ref().is_some_and(|pending| {
            pending.qr.id == self.qr.id
                && identity
                    .roster()
                    .verifies_addition(
                        &pending.base,
                        pending.joining_device(),
                        &pending.trusted.device_id,
                    )
                    .is_ok()
        })
    }

    pub(super) fn check_offer(
        &self,
        signer: &str,
        roster: &DeviceRoster,
        trusted: &DeviceDescriptor,
        joining: &Option<DeviceDescriptor>,
    ) -> Result<()> {
        let devices = roster.devices()?;
        let candidate = self.joining.as_ref().ok_or_else(invalid)?;
        let pinned = if self.qr.is_current() {
            &self.qr.device
        } else {
            self.trusted.as_ref().ok_or_else(invalid)?
        };
        let offered = joining
            .as_ref()
            .or_else(|| (!self.qr.is_current()).then_some(&self.qr.device));
        if signer != trusted.signing_public_key
            || trusted != pinned
            || offered != Some(candidate)
            || !devices.contains(trusted)
            || devices.iter().any(|d| {
                d.device_id == candidate.device_id || d.moss_peer_id == candidate.moss_peer_id
            })
        {
            return Err(invalid());
        }
        if let Some(known) = &self.trusted {
            if known != trusted {
                return Err(invalid());
            }
        }
        if let Some(base) = &self.base {
            if base.digest()? != roster.digest()? {
                return Err(invalid());
            }
        }
        Ok(())
    }

    pub(super) fn resume(pending: &PendingJoin, identity: &DeviceIdentity) -> Result<Self> {
        let packet = wire::seal(
            &pending.qr,
            &identity.key(),
            wire::LinkMessage::Ready {
                offer_hash: pending.base.digest()?,
            },
        )?;
        Ok(Self {
            qr: pending.qr.clone(),
            joining: Some(pending.joining_device().clone()),
            role: Role::Joining,
            trusted: Some(pending.trusted.clone()),
            base: Some(pending.base.clone()),
            packet: Some(packet),
            last_send: None,
            last_response: Instant::now(),
        })
    }

    pub(super) fn peer(&self) -> Option<&str> {
        match self.role {
            Role::Authorizing => self.joining.as_ref().map(|d| d.moss_peer_id.as_str()),
            Role::Joining => self.trusted.as_ref().map(|d| d.moss_peer_id.as_str()),
        }
    }
}
