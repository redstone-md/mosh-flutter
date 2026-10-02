use std::time::Duration;

use super::*;

const RETRY_INTERVAL: Duration = Duration::from_millis(500);
const CONNECTION_NOTICE_AFTER: Duration = Duration::from_secs(15);

fn due(sent: Option<Instant>) -> bool {
    sent.is_none_or(|last| last.elapsed() >= RETRY_INTERVAL)
}

impl DeviceLinkRuntime {
    /// Drive pairing even while its settings section is closed.
    pub fn service(&mut self) -> Result<()> {
        self.identity.reload()?;
        self.reconcile_removal()?;
        self.expire()?;
        for message in self.transport.drain() {
            // Unauthenticated traffic never changes consent or membership.
            if let Err(error) = self.receive(&message.payload) {
                if error.kind == DeviceLinkErrorKind::Storage {
                    return Err(error);
                }
            }
        }
        self.retry_exchange();
        self.retry_delivery();
        self.retry_roster();
        Ok(())
    }

    /// DM adoption can save this device's removal before its roster notice arrives.
    pub(super) fn reconcile_removal(&mut self) -> Result<()> {
        let authorizing = self
            .exchange
            .as_ref()
            .is_some_and(|e| e.role == Role::Authorizing);
        let lost_pending_join = self.exchange.as_ref().is_some_and(|e| {
            e.role == Role::Joining && e.base.is_some() && self.identity.record.pending.is_none()
        });
        if self.identity.revoked()?
            && (authorizing
                || lost_pending_join
                || matches!(
                    self.phase,
                    DeviceLinkPhase::Delivering | DeviceLinkPhase::Linked
                ))
        {
            self.exchange = None;
            self.phase = DeviceLinkPhase::Idle;
            self.error = None;
        }
        Ok(())
    }

    pub(super) fn expire(&mut self) -> Result<()> {
        let Some(exchange) = &self.exchange else {
            return Ok(());
        };
        if exchange.qr.expires_at <= now() {
            self.fail(DeviceLinkErrorKind::Expired)?;
        } else if exchange.role == Role::Joining
            && !self.identity.can_join()?
            && !exchange.awaits_adopted_approval(&self.identity)
        {
            self.reject(DeviceLinkErrorKind::Ineligible)?;
        }
        Ok(())
    }

    fn retry_exchange(&mut self) {
        let Some(e) = self.exchange.as_mut() else {
            return;
        };
        let (Some(peer), Some(packet)) = (e.peer(), &e.packet) else {
            return;
        };
        if !due(e.last_send) {
            return;
        }
        let sent = self.transport.send(peer, packet).is_ok();
        e.last_send = Some(Instant::now());
        if e.last_response.elapsed() >= CONNECTION_NOTICE_AFTER {
            self.error = Some(DeviceLinkErrorKind::ConnectionLost);
        } else if sent {
            self.error = None;
        }
    }

    fn retry_delivery(&mut self) {
        let Some(delivery) = &self.identity.record.delivery else {
            return;
        };
        if !due(self.delivery_last_send) {
            return;
        }
        let sent = self
            .transport
            .send(&delivery.joining_device().moss_peer_id, &delivery.packet)
            .is_ok();
        self.delivery_last_send = Some(Instant::now());
        // Sending is insufficient proof. Require the signed durable-save ack.
        if self.delivery_started.elapsed() >= CONNECTION_NOTICE_AFTER {
            self.error = Some(DeviceLinkErrorKind::ConnectionLost);
        }
        if !sent {
            self.phase = DeviceLinkPhase::Delivering;
        }
    }
}
