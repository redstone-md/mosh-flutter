mod actions;
mod exchange;
#[cfg(test)]
mod legacy_tests;
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
    DeviceDescriptor, DeviceLinkError, DeviceLinkErrorKind, DeviceLinkPhase,
    DeviceLinkRole as Role, DeviceLinkSnapshot, Result,
};
use crate::persistence::Persistence;
use crate::shared_node::SharedMossNode;
use exchange::Exchange;

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
                e.joining.as_ref().unwrap(),
            )?),
            _ => None,
        };
        Ok(DeviceLinkSnapshot {
            role: exchange.map(|e| e.role).or_else(|| {
                self.identity
                    .record
                    .delivery
                    .as_ref()
                    .map(|_| Role::Authorizing)
            }),
            revoked: self.identity.revoked()?,
            revocations: self.identity.revocations()?,
            user_id: self.identity.roster().user_id(),
            own_device_id: self.identity.device().device_id.clone(),
            devices: self.identity.roster().devices()?,
            can_join: self.identity.can_join()?,
            phase: self.phase,
            qr_uri: exchange
                .filter(|e| e.role == Role::Authorizing && self.phase == DeviceLinkPhase::ShowingQr)
                .map(|e| e.qr.uri())
                .transpose()?,
            expires_at: exchange.map(|e| e.qr.expires_at),
            confirmation_code,
            pending_device: exchange.and_then(|e| match e.role {
                Role::Authorizing => e.joining.clone(),
                Role::Joining => e.trusted.clone(),
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
