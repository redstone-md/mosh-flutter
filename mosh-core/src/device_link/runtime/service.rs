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
        Ok(())
    }

    fn expire(&mut self) -> Result<()> {
        if self
            .exchange
            .as_ref()
            .is_some_and(|e| e.qr.expires_at <= now())
        {
            self.fail(DeviceLinkErrorKind::Expired)?;
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
            .send(&delivery.qr.device.moss_peer_id, &delivery.packet)
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
