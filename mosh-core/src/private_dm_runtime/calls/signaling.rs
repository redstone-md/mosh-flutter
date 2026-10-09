use super::*;

impl PrivateDmSession {
    pub(in crate::private_dm_runtime) fn pump_call_signaling(&mut self, now: u64) {
        self.call_occupancy.expire(now);
        for (call_id, action) in self.call_ends.due(now) {
            let _ = self.publish_authenticated_call(&call_id, action);
        }
        let Some(call) = &self.call else {
            return;
        };
        let call_id = call.call_id.clone();
        if matches!(call.phase, CallPhase::Outgoing | CallPhase::Accepting)
            && now.saturating_sub(call.offer_first_ms) >= CALL_RING_TIMEOUT_MS
        {
            let _ = self.call_end(&call_id, "no_answer");
            return;
        }
        if now.saturating_sub(call.offer_last_ms) < CALL_RESEND_MS {
            return;
        }
        let Some(action) = call.outbound_control() else {
            return;
        };
        match self.publish_authenticated_call(&call_id, action) {
            Err(error) => dlog::write(
                LogLevel::Error,
                kinds::CALL,
                &call_id,
                &format!("call control resend failed: {error}"),
            ),
            Ok(()) => {
                if let Some(call) = self.call.as_mut() {
                    call.mark_offer_sent(now);
                }
            }
        }
    }
}
