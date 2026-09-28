use super::*;
use crate::device_link::identity::LinkDelivery;
use crate::device_link::roster::{invalid, MAX_NAME_CHARS};
use crate::device_link::wire::{self, LinkMessage};

impl DeviceLinkRuntime {
    pub fn create_qr(&mut self, name: String) -> Result<DeviceLinkSnapshot> {
        self.ensure_idle()?;
        if !self.identity.can_join()? {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Ineligible));
        }
        let name = name.trim();
        if name.is_empty()
            || name.chars().count() > MAX_NAME_CHARS
            || name.chars().any(char::is_control)
        {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::InvalidQr));
        }
        let mut record = self.identity.record.clone();
        record.device.name = name.into();
        record.roster = DeviceRoster::genesis(record.device.clone(), &self.identity.key())?;
        self.identity.update(record)?;
        self.exchange = Some(Exchange {
            qr: PairingQr::new(self.identity.device().clone(), now()),
            role: Role::Joining,
            trusted: None,
            base: None,
            packet: None,
            last_send: None,
            last_response: Instant::now(),
        });
        self.phase = DeviceLinkPhase::ShowingQr;
        self.error = None;
        self.snapshot()
    }

    pub fn import_qr(&mut self, uri: String) -> Result<DeviceLinkSnapshot> {
        self.ensure_idle()?;
        let qr = PairingQr::parse(&uri, now())?;
        let existing = self.identity.roster().devices()?;
        if existing
            .iter()
            .any(|d| d.device_id == qr.device.device_id || d.moss_peer_id == qr.device.moss_peer_id)
        {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::InvalidQr));
        }
        let packet = wire::seal(
            &qr,
            &self.identity.key(),
            LinkMessage::Offer {
                roster: self.identity.roster().clone(),
                trusted: self.identity.device().clone(),
            },
        )?;
        self.exchange = Some(Exchange {
            qr,
            role: Role::Trusted,
            trusted: Some(self.identity.device().clone()),
            base: Some(self.identity.roster().clone()),
            packet: Some(packet),
            last_send: None,
            last_response: Instant::now(),
        });
        self.phase = DeviceLinkPhase::Connecting;
        self.error = None;
        self.snapshot()
    }

    pub fn approve(&mut self, code: String) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        let e = self.exchange.as_ref().ok_or_else(invalid)?;
        if e.role != Role::Trusted || self.phase != DeviceLinkPhase::AwaitingApproval {
            return Err(invalid());
        }
        let base = e.base.as_ref().ok_or_else(invalid)?;
        let expected = e.qr.code(&base.digest()?, self.identity.device())?;
        if code.trim().to_ascii_uppercase() != expected {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::CodeMismatch));
        }
        if base.digest()? != self.identity.roster().digest()? {
            return Err(invalid());
        }
        let roster = base.extend(e.qr.device.clone(), &self.identity.key())?;
        let packet = wire::seal(
            &e.qr,
            &self.identity.key(),
            LinkMessage::Approved {
                roster: roster.clone(),
            },
        )?;
        let mut record = self.identity.record.clone();
        record.delivery = Some(LinkDelivery {
            qr: e.qr.clone(),
            packet,
            roster_hash: roster.digest()?,
        });
        record.roster = roster;
        self.identity.update(record)?;
        self.exchange = None;
        self.phase = DeviceLinkPhase::Delivering;
        self.error = None;
        self.delivery_started = Instant::now();
        self.delivery_last_send = None;
        self.snapshot()
    }

    pub fn cancel(&mut self) -> Result<DeviceLinkSnapshot> {
        if self.identity.record.delivery.is_some() {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Busy));
        }
        if let Some(e) = &self.exchange {
            if let Some(peer) = e.peer() {
                let packet = wire::seal(&e.qr, &self.identity.key(), LinkMessage::Rejected)?;
                let _ = self.transport.send(peer, &packet);
            }
        }
        self.fail(DeviceLinkErrorKind::Rejected)?;
        self.snapshot()
    }
}
