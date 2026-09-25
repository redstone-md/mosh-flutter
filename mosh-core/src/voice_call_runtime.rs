//! Per-session voice-call state. Owned by `PrivateDmRuntime`; one instance
//! per private-DM session. A pure state machine: the media frames of an
//! active call live in the call media hub (`private_dm_runtime::CallMedia`),
//! not here, so the audio loop never waits on the runtime.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallDirection {
    Caller,
    Callee,
}

impl CallDirection {
    pub fn as_str(self) -> &'static str {
        match self {
            CallDirection::Caller => "caller",
            CallDirection::Callee => "callee",
        }
    }

    /// The bit our own frames carry at the top of their sequence number.
    pub(crate) fn seq_direction_bit(self) -> u64 {
        match self {
            CallDirection::Caller => 0,
            CallDirection::Callee => 1 << 63,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallPhase {
    Outgoing,
    Ringing,
    Active,
}

#[derive(Debug)]
pub struct CallState {
    pub call_id: String,
    pub direction: CallDirection,
    pub phase: CallPhase,
    pub key_b64: String,
    pub nonce_prefix_b64: String,
    /// Unix millis the call entered `Active`, set when both sides have agreed.
    pub started_at_ms: u64,
    /// Counterparty device id captured on offer/accept.
    pub remote_device: String,
    /// Caller-only ring bookkeeping: when the first `CallOffer` went out and
    /// when the last one did. The offer is retransmitted on a cadence until the
    /// callee's `CallAccept` lands, and the ring budget is measured from the
    /// first send. Both stay 0 on the callee.
    pub offer_first_ms: u64,
    pub offer_last_ms: u64,
}

impl CallState {
    pub fn outgoing(
        call_id: String,
        key_b64: String,
        nonce_prefix_b64: String,
        remote_device: String,
    ) -> Self {
        Self {
            call_id,
            direction: CallDirection::Caller,
            phase: CallPhase::Outgoing,
            key_b64,
            nonce_prefix_b64,
            started_at_ms: 0,
            remote_device,
            offer_first_ms: 0,
            offer_last_ms: 0,
        }
    }

    pub fn ringing(
        call_id: String,
        key_b64: String,
        nonce_prefix_b64: String,
        remote_device: String,
    ) -> Self {
        Self {
            call_id,
            direction: CallDirection::Callee,
            phase: CallPhase::Ringing,
            key_b64,
            nonce_prefix_b64,
            started_at_ms: 0,
            remote_device,
            offer_first_ms: 0,
            offer_last_ms: 0,
        }
    }

    pub fn become_active(&mut self, now_ms: u64) {
        self.phase = CallPhase::Active;
        self.started_at_ms = now_ms;
    }

    /// Stamp an outbound `CallOffer`. The first stamp also starts the ring
    /// budget, so the caller gives up a fixed time after the call began rather
    /// than a fixed time after the latest retransmit.
    pub fn mark_offer_sent(&mut self, now_ms: u64) {
        if self.offer_first_ms == 0 {
            self.offer_first_ms = now_ms;
        }
        self.offer_last_ms = now_ms;
    }

    /// Call-log classification: a call that never reached `Active` is "missed",
    /// regardless of who hung up or why; only an answered call is "completed".
    pub fn end_kind(&self) -> &'static str {
        if self.phase != CallPhase::Active {
            "missed"
        } else {
            "completed"
        }
    }

    pub fn duration_ms(&self, now_ms: u64) -> u64 {
        if self.started_at_ms == 0 || now_ms < self.started_at_ms {
            0
        } else {
            now_ms - self.started_at_ms
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn become_active_records_timestamp() {
        let mut call = CallState::outgoing("c".into(), "k".into(), "n".into(), "peer".into());
        assert_eq!(call.phase, CallPhase::Outgoing);
        call.become_active(1_000);
        assert_eq!(call.phase, CallPhase::Active);
        assert_eq!(call.started_at_ms, 1_000);
    }

    #[test]
    fn end_kind_is_missed_until_active_regardless_of_reason() {
        // A call that never reached Active is "missed" however it ends — a peer
        // hangup ("hangup") of an unanswered call must not log as "completed".
        let mut ringing = CallState::ringing("c".into(), "k".into(), "n".into(), "peer".into());
        assert_eq!(ringing.end_kind(), "missed");
        let mut outgoing = CallState::outgoing("c".into(), "k".into(), "n".into(), "peer".into());
        assert_eq!(outgoing.end_kind(), "missed");

        ringing.become_active(1_000);
        outgoing.become_active(1_000);
        assert_eq!(ringing.end_kind(), "completed");
        assert_eq!(outgoing.end_kind(), "completed");
    }

    #[test]
    fn duration_ms_anchors_on_started_at() {
        let mut call = CallState::outgoing("c".into(), "k".into(), "n".into(), "peer".into());
        assert_eq!(call.duration_ms(5_000), 0);
        call.become_active(2_000);
        assert_eq!(call.duration_ms(5_000), 3_000);
    }
}
