use super::*;
use crate::device_link::identity::LinkReceipt;
use crate::device_link::roster::invalid;
use crate::device_link::wire::{self, LinkMessage};

impl DeviceLinkRuntime {
    pub(super) fn receive(&mut self, packet: &[u8]) -> Result<()> {
        if self.receive_names(packet)? {
            return Ok(());
        }
        if self.receive_roster(packet)? {
            return Ok(());
        }
        if self.receive_delivery(packet)? || self.receive_receipt(packet)? {
            return Ok(());
        }
        let Some(e) = self.exchange.as_ref() else {
            return Ok(());
        };
        let (signer, message) = wire::open(&e.qr, packet)?;
        match (e.role, message) {
            (Role::Authorizing, LinkMessage::Join { device }) => self.join(signer, device),
            (
                Role::Joining,
                LinkMessage::Offer {
                    roster,
                    trusted,
                    joining,
                },
            ) => self.offer(signer, roster, trusted, joining),
            (Role::Authorizing, LinkMessage::Ready { offer_hash }) => {
                self.ready(signer, offer_hash)
            }
            (Role::Joining, LinkMessage::Approved { roster }) => self.approved(signer, roster),
            (_, LinkMessage::Rejected) => {
                let expected = match e.role {
                    Role::Authorizing => {
                        let Some(joining) = &e.joining else {
                            return Ok(());
                        };
                        &joining.signing_public_key
                    }
                    Role::Joining => &e.trusted.as_ref().ok_or_else(invalid)?.signing_public_key,
                };
                if &signer == expected {
                    self.fail(DeviceLinkErrorKind::Rejected)?;
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }

    fn receive_delivery(&mut self, packet: &[u8]) -> Result<bool> {
        let Some(d) = &self.identity.record.delivery else {
            return Ok(false);
        };
        let Ok((signer, LinkMessage::Ack { roster_hash })) = wire::open(&d.qr, packet) else {
            return Ok(false);
        };
        if signer != d.joining_device().signing_public_key || roster_hash != d.roster_hash {
            return Err(invalid());
        }
        let mut record = self.identity.record.clone();
        record.delivery = None;
        self.identity.update(record)?;
        self.phase = DeviceLinkPhase::Linked;
        self.error = None;
        Ok(true)
    }

    fn join(&mut self, signer: String, device: DeviceDescriptor) -> Result<()> {
        device.validate()?;
        if signer != device.signing_public_key || self.identity.revoked()? {
            return Err(invalid());
        }
        let e = self.exchange.as_mut().ok_or_else(invalid)?;
        if let Some(frozen) = &e.joining {
            if frozen != &device {
                return Err(invalid());
            }
            e.last_send = None;
            return Ok(());
        }
        if self
            .identity
            .roster()
            .devices()?
            .iter()
            .any(|d| d.device_id == device.device_id || d.moss_peer_id == device.moss_peer_id)
        {
            return Err(invalid());
        }
        let base = self.identity.roster().clone();
        let packet = wire::seal(
            &e.qr,
            &self.identity.key(),
            LinkMessage::Offer {
                roster: base.clone(),
                trusted: self.identity.device().clone(),
                joining: Some(device.clone()),
            },
        )?;
        e.joining = Some(device);
        e.base = Some(base);
        e.packet = Some(packet);
        e.last_send = None;
        e.last_response = Instant::now();
        self.phase = DeviceLinkPhase::Connecting;
        Ok(())
    }

    fn receive_receipt(&mut self, packet: &[u8]) -> Result<bool> {
        let Some(r) = &self.identity.record.receipt else {
            return Ok(false);
        };
        let Ok((signer, LinkMessage::Approved { roster })) = wire::open(&r.qr, packet) else {
            return Ok(false);
        };
        if signer != r.trusted.signing_public_key || roster.digest()? != r.roster_hash {
            return Err(invalid());
        }
        let _ = self.transport.send(&r.trusted.moss_peer_id, &r.packet);
        Ok(true)
    }

    fn offer(
        &mut self,
        signer: String,
        roster: DeviceRoster,
        trusted: DeviceDescriptor,
        joining: Option<DeviceDescriptor>,
    ) -> Result<()> {
        let e = self.exchange.as_ref().ok_or_else(invalid)?;
        e.check_offer(&signer, &roster, &trusted, &joining)?;
        if self.identity.revoked()? && !roster.extends(self.identity.roster())? {
            return Err(invalid());
        }
        let message = LinkMessage::Ready {
            offer_hash: roster.digest()?,
        };
        let packet = wire::seal(&e.qr, &self.identity.key(), message)?;
        if e.base.is_none() {
            let mut record = self.identity.record.clone();
            record.pending = Some(PendingJoin {
                qr: e.qr.clone(),
                joining: e.joining.clone(),
                trusted: trusted.clone(),
                base: roster.clone(),
            });
            self.identity.update(record)?;
        }
        let e = self.exchange.as_mut().ok_or_else(invalid)?;
        e.packet = Some(packet);
        e.trusted = Some(trusted);
        e.base = Some(roster);
        e.last_send = None;
        e.last_response = Instant::now();
        self.phase = DeviceLinkPhase::AwaitingConfirmation;
        self.error = None;
        Ok(())
    }

    fn ready(&mut self, signer: String, offer_hash: String) -> Result<()> {
        let e = self.exchange.as_mut().ok_or_else(invalid)?;
        if signer != e.joining.as_ref().ok_or_else(invalid)?.signing_public_key
            || offer_hash != e.base.as_ref().ok_or_else(invalid)?.digest()?
        {
            return Err(invalid());
        }
        self.phase = DeviceLinkPhase::AwaitingApproval;
        e.last_response = Instant::now();
        self.error = None;
        Ok(())
    }

    fn approved(&mut self, signer: String, roster: DeviceRoster) -> Result<()> {
        let e = self.exchange.as_ref().ok_or_else(invalid)?;
        let trusted = e.trusted.as_ref().ok_or_else(invalid)?;
        if signer != trusted.signing_public_key {
            return Err(invalid());
        }
        roster.verifies_addition(
            e.base.as_ref().ok_or_else(invalid)?,
            e.joining.as_ref().ok_or_else(invalid)?,
            &trusted.device_id,
        )?;
        let hash = roster.digest()?;
        let already_adopted =
            e.awaits_adopted_approval(&self.identity) && hash == self.identity.roster().digest()?;
        if self.identity.revoked()? && !roster.extends(self.identity.roster())? {
            return Err(invalid());
        }
        if !self.identity.can_join()? && !already_adopted {
            return Err(invalid());
        }
        let ack = wire::seal(
            &e.qr,
            &self.identity.key(),
            LinkMessage::Ack {
                roster_hash: hash.clone(),
            },
        )?;
        let mut record = self.identity.record.clone();
        record.roster = roster;
        record.account_certificate = None;
        record.pending = None;
        record.consume(&e.qr, now());
        record.receipt = Some(LinkReceipt {
            qr: e.qr.clone(),
            trusted: trusted.clone(),
            roster_hash: hash,
            packet: ack.clone(),
        });
        self.identity.update(record)?;
        let _ = self.transport.send(&trusted.moss_peer_id, &ack);
        self.exchange = None;
        self.phase = DeviceLinkPhase::Linked;
        self.error = None;
        Ok(())
    }
}
