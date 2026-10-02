use super::*;
use crate::device_link::identity::LinkDelivery;
use crate::device_link::roster::{invalid, MAX_NAME_CHARS};
use crate::device_link::wire::{self, LinkMessage};

impl DeviceLinkRuntime {
    pub fn begin_link(&mut self) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        self.ensure_idle()?;
        if self.identity.revoked()? {
            return Err(invalid());
        }
        self.exchange = Some(Exchange {
            qr: PairingQr::new(self.identity.device().clone(), now()),
            joining: None,
            role: Role::Authorizing,
            trusted: Some(self.identity.device().clone()),
            base: None,
            packet: None,
            last_send: None,
            last_response: Instant::now(),
        });
        self.phase = DeviceLinkPhase::ShowingQr;
        self.error = None;
        self.snapshot()
    }

    pub fn join_link(&mut self, uri: String, name: String) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        self.ensure_idle()?;
        if !self.identity.can_join()? {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Ineligible));
        }
        let qr = PairingQr::parse(&uri, now())?;
        if self.identity.record.consumed(&qr, now())
            || qr.device.device_id == self.identity.device().device_id
            || qr.device.moss_peer_id == self.identity.device().moss_peer_id
        {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::InvalidQr));
        }
        self.prepare_join_name(&name)?;
        let joining = self.identity.device().clone();
        let packet = wire::seal(
            &qr,
            &self.identity.key(),
            LinkMessage::Join {
                device: joining.clone(),
            },
        )?;
        self.exchange = Some(Exchange {
            trusted: Some(qr.device.clone()),
            qr,
            joining: Some(joining),
            role: Role::Joining,
            base: None,
            packet: Some(packet),
            last_send: None,
            last_response: Instant::now(),
        });
        self.phase = DeviceLinkPhase::Connecting;
        self.error = None;
        self.snapshot()
    }

    fn prepare_join_name(&mut self, typed: &str) -> Result<()> {
        let revoked = self.identity.revoked()?;
        let name = join_name(&self.identity.device().name, typed, revoked)?;
        let mut record = self.identity.record.clone();
        if !revoked {
            record.device.name = name.into();
            record.roster = DeviceRoster::genesis(record.device.clone(), &self.identity.key())?;
        }
        record.pending = None;
        self.identity.update(record)
    }

    pub fn approve(&mut self, code: String) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        let e = self.exchange.as_ref().ok_or_else(invalid)?;
        if e.role != Role::Authorizing || self.phase != DeviceLinkPhase::AwaitingApproval {
            return Err(invalid());
        }
        let base = e.base.as_ref().ok_or_else(invalid)?;
        let joining = e.joining.as_ref().ok_or_else(invalid)?;
        let expected =
            e.qr.code(&base.digest()?, self.identity.device(), joining)?;
        if code.trim().to_ascii_uppercase() != expected {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::CodeMismatch));
        }
        if base.digest()? != self.identity.roster().digest()? {
            return Err(invalid());
        }
        let roster = base.extend(joining.clone(), &self.identity.key())?;
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
            joining: Some(joining.clone()),
            packet,
            roster_hash: roster.digest()?,
        });
        record.roster = roster;
        record.consume(&e.qr, now());
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
        self.reject(DeviceLinkErrorKind::Rejected)?;
        self.snapshot()
    }

    pub(super) fn reject(&mut self, kind: DeviceLinkErrorKind) -> Result<()> {
        let rejection = self
            .exchange
            .as_ref()
            .and_then(|e| e.peer().map(|peer| (peer.to_owned(), &e.qr)))
            .map(|(peer, qr)| {
                wire::seal(qr, &self.identity.key(), LinkMessage::Rejected)
                    .map(|packet| (peer, packet))
            })
            .transpose()?;
        self.fail(kind)?;
        if let Some((peer, packet)) = rejection {
            let _ = self.transport.send(&peer, &packet);
        }
        Ok(())
    }
}

/// The name the joining device announces. A blank field keeps the current
/// name, so linking works without typing one; a removed device always keeps
/// its own.
fn join_name<'a>(current: &'a str, typed: &'a str, revoked: bool) -> Result<&'a str> {
    let typed = typed.trim();
    let name = if revoked || typed.is_empty() {
        current
    } else {
        typed
    };
    if name.is_empty()
        || name.chars().count() > MAX_NAME_CHARS
        || name.chars().any(char::is_control)
    {
        return Err(DeviceLinkError::new(DeviceLinkErrorKind::InvalidQr));
    }
    Ok(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blank_name_keeps_the_current_one() {
        assert_eq!(join_name("Desktop", "   ", false).unwrap(), "Desktop");
        assert_eq!(join_name("Desktop", " Office ", false).unwrap(), "Office");
    }

    #[test]
    fn a_removed_device_keeps_its_name() {
        assert_eq!(join_name("Desktop", "Office", true).unwrap(), "Desktop");
    }

    #[test]
    fn an_unusable_name_is_refused() {
        let long = "x".repeat(MAX_NAME_CHARS + 1);
        assert!(join_name("Desktop", &long, false).is_err());
        assert!(join_name("Desktop", "a\nb", false).is_err());
        assert!(join_name("", " ", false).is_err());
    }
}
