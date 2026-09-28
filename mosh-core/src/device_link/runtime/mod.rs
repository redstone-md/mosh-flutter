mod actions;
mod receive;
mod revocation;
mod service;

use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use super::identity::{DeviceIdentity, PendingJoin};
use super::qr::PairingQr;
use super::roster::DeviceRoster;
use super::transport::LinkTransport;
use super::types::{
    DeviceDescriptor, DeviceLinkError, DeviceLinkErrorKind, DeviceLinkPhase, DeviceLinkSnapshot,
    Result,
};
use crate::persistence::Persistence;
use crate::shared_node::SharedMossNode;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Joining,
    Trusted,
}

struct Exchange {
    qr: PairingQr,
    role: Role,
    trusted: Option<DeviceDescriptor>,
    base: Option<DeviceRoster>,
    packet: Option<Vec<u8>>,
    last_send: Option<Instant>,
    last_response: Instant,
}

impl Exchange {
    fn check_offer(
        &self,
        signer: &str,
        roster: &DeviceRoster,
        trusted: &DeviceDescriptor,
    ) -> Result<()> {
        use super::roster::invalid;
        let devices = roster.devices()?;
        if signer != trusted.signing_public_key
            || !devices.contains(trusted)
            || devices.iter().any(|d| {
                d.device_id == self.qr.device.device_id
                    || d.moss_peer_id == self.qr.device.moss_peer_id
            })
        {
            return Err(invalid());
        }
        if let Some(known) = &self.trusted {
            if known != trusted
                || self.base.as_ref().ok_or_else(invalid)?.digest()? != roster.digest()?
            {
                return Err(invalid());
            }
        }
        Ok(())
    }

    fn resume(pending: &PendingJoin, identity: &DeviceIdentity) -> Result<Self> {
        let packet = super::wire::seal(
            &pending.qr,
            &identity.key(),
            super::wire::LinkMessage::Ready {
                offer_hash: pending.base.digest()?,
            },
        )?;
        Ok(Self {
            qr: pending.qr.clone(),
            role: Role::Joining,
            trusted: Some(pending.trusted.clone()),
            base: Some(pending.base.clone()),
            packet: Some(packet),
            last_send: None,
            last_response: Instant::now(),
        })
    }

    fn peer(&self) -> Option<&str> {
        match self.role {
            Role::Trusted => Some(&self.qr.device.moss_peer_id),
            Role::Joining => self.trusted.as_ref().map(|d| d.moss_peer_id.as_str()),
        }
    }
}

pub struct DeviceLinkRuntime {
    identity: DeviceIdentity,
    transport: LinkTransport,
    exchange: Option<Exchange>,
    phase: DeviceLinkPhase,
    error: Option<DeviceLinkErrorKind>,
    delivery_last_send: Option<Instant>,
    delivery_started: Instant,
    roster_last_send: Option<Instant>,
}

impl DeviceLinkRuntime {
    pub fn open(shared: Arc<SharedMossNode>, store: Arc<Persistence>) -> Result<Self> {
        let transport = LinkTransport::new(shared)?;
        let identity = DeviceIdentity::open(store, &transport.peer_id()?)?;
        let exchange = identity
            .record
            .pending
            .as_ref()
            .map(|pending| Exchange::resume(pending, &identity))
            .transpose()?;
        let phase = if identity.record.delivery.is_some() {
            DeviceLinkPhase::Delivering
        } else if exchange.is_some() {
            DeviceLinkPhase::AwaitingConfirmation
        } else {
            DeviceLinkPhase::Idle
        };
        let mut runtime = Self {
            identity,
            transport,
            exchange,
            phase,
            error: None,
            delivery_last_send: None,
            delivery_started: Instant::now(),
            roster_last_send: None,
        };
        runtime.expire()?;
        Ok(runtime)
    }

    pub fn snapshot(&mut self) -> Result<DeviceLinkSnapshot> {
        self.service()?;
        let exchange = self.exchange.as_ref();
        let joining = exchange.filter(|e| e.role == Role::Joining);
        let confirmation_code = match joining {
            Some(e) if e.trusted.is_some() && e.base.is_some() => Some(e.qr.code(
                &e.base.as_ref().unwrap().digest()?,
                e.trusted.as_ref().unwrap(),
            )?),
            _ => None,
        };
        Ok(DeviceLinkSnapshot {
            revoked: self.identity.revoked()?,
            revocations: self.identity.revocations()?,
            user_id: self.identity.roster().user_id(),
            own_device_id: self.identity.device().device_id.clone(),
            devices: self.identity.roster().devices()?,
            can_join: self.identity.can_join()?,
            phase: self.phase,
            qr_uri: joining.map(|e| e.qr.uri()).transpose()?,
            expires_at: exchange.map(|e| e.qr.expires_at),
            confirmation_code,
            pending_device: exchange.map(|e| match e.role {
                Role::Trusted => e.qr.device.clone(),
                Role::Joining => e.trusted.clone().unwrap_or_else(|| e.qr.device.clone()),
            }),
            error: self.error,
        })
    }

    fn ensure_idle(&self) -> Result<()> {
        if self.exchange.is_some() || self.identity.record.delivery.is_some() {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Busy));
        }
        Ok(())
    }

    fn fail(&mut self, kind: DeviceLinkErrorKind) -> Result<()> {
        if let Some(exchange) = &self.exchange {
            let mut record = self.identity.record.clone();
            record.pending = None;
            record.consume(&exchange.qr, now());
            self.identity.update(record)?;
        }
        self.exchange = None;
        self.phase = DeviceLinkPhase::Failed;
        self.error = Some(kind);
        Ok(())
    }
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
