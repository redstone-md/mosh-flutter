//! Authenticated call controls; the caller confirms the participating receiver.

mod authentication;
mod book;
mod history;
mod occupancy;
mod offer;
mod protocol;
mod receive;
mod signaling;
mod terminal;

use super::*;
pub(crate) use book::CallProtocolBook;
pub(super) use occupancy::CallOccupancy;
use protocol::CallAction;
pub(super) use terminal::CallEndRetries;

impl PrivateDmSession {
    pub(super) fn send_call_control(
        &self,
        envelope: &ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        let payload = serde_json::to_vec(envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)
    }

    pub(super) fn publish_call_offer(
        &mut self,
        call_id: &str,
        key_b64: &str,
        nonce_prefix_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.publish_authenticated_call(
            call_id,
            CallAction::Offer {
                key_b64: key_b64.into(),
                nonce_prefix_b64: nonce_prefix_b64.into(),
                native: protocol::native_platform(),
            },
        )
    }

    pub(super) fn publish_call_accept(
        &mut self,
        call_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.publish_authenticated_call(call_id, CallAction::Answer)
    }

    pub(super) fn call_start(&mut self) -> Result<CallStarted, PrivateDmRuntimeError> {
        if !self.ready_for_user_actions() {
            return Err(PrivateDmRuntimeError::NotReady);
        }
        if self.call.is_some() {
            return Err(PrivateDmRuntimeError::Attachment(
                "another call is already in flight".into(),
            ));
        }
        let call_id = self.crypto.random_token("call")?;
        let key_b64 = random_b64(32);
        let nonce_prefix_b64 = random_b64(4);
        let mut call = CallState::outgoing(
            call_id.clone(),
            key_b64.clone(),
            nonce_prefix_b64.clone(),
            String::new(),
        );
        call.caller_signer = hex::encode(self.crypto.signer_public());
        self.call = Some(call);
        if let Err(error) = self
            .transport
            .subscribe(&self.mesh_id, &voice_call_channel(&call_id))
            .map_err(PrivateDmRuntimeError::Moss)
            .and_then(|()| self.publish_call_offer(&call_id, &key_b64, &nonce_prefix_b64))
        {
            self.call = None;
            let _ = self
                .transport
                .unsubscribe(&self.mesh_id, &voice_call_channel(&call_id));
            return Err(error);
        }
        self.call
            .as_mut()
            .expect("call installed")
            .mark_offer_sent(now_ms());
        Ok(CallStarted {
            session_id: self.session_id.clone(),
            call_id,
            key_b64,
            nonce_prefix_b64,
        })
    }

    pub(super) fn call_accept(&mut self, call_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let call = self
            .call
            .as_ref()
            .ok_or(PrivateDmRuntimeError::MissingSession)?;
        if call.call_id != call_id
            || !matches!(call.phase, CallPhase::Ringing | CallPhase::Accepting)
        {
            return Err(PrivateDmRuntimeError::MissingSession);
        }
        self.publish_call_accept(call_id)?;
        if let Some(call) = self.call.as_mut() {
            call.phase = CallPhase::Accepting;
            call.mark_offer_sent(now_ms());
        }
        Ok(())
    }

    pub(super) fn call_decline(
        &mut self,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if !self.holds_call(call_id) {
            return Ok(());
        }
        self.publish_authenticated_call(
            call_id,
            CallAction::Decline {
                reason: reason.into(),
            },
        )?;
        self.call_ends.remember(
            call_id,
            CallAction::Decline {
                reason: reason.into(),
            },
            now_ms(),
        );
        self.finish_call("missed", 0);
        Ok(())
    }

    pub(super) fn call_end(
        &mut self,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref().filter(|call| call.matches_id(call_id)) else {
            return Ok(());
        };
        let call_id = call.call_id.clone();
        let caller_signer = call.caller_signer.clone();
        let (kind, duration) = (call.end_kind(), call.duration_ms(now_ms()));
        self.call_ends.remember(
            &call_id,
            CallAction::End {
                caller: caller_signer.clone(),
                reason: reason.into(),
            },
            now_ms(),
        );
        let outcome = self.publish_authenticated_call(
            &call_id,
            CallAction::End {
                caller: caller_signer,
                reason: reason.into(),
            },
        );
        self.finish_call(kind, duration);
        outcome
    }

    pub(super) fn handle_call_control(
        &mut self,
        envelope: ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        let ControlEnvelope::CallControl {
            session_id,
            ciphertext_b64,
        } = envelope
        else {
            return Ok(());
        };
        if session_id != self.session_id {
            return Ok(());
        }
        let control = self.decrypt_call_control(&ciphertext_b64)?;
        let terminal = matches!(
            control.action,
            CallAction::End { .. } | CallAction::Decline { .. }
        );
        // Media has its own immutable binding and idempotence rules. Its fresh
        // retry must not suppress an earlier caller selection or end control.
        let media = matches!(control.action, CallAction::Media(_));
        let outcome = if media
            || self
                .call_controls
                .receive(&control.signer, control.sequence)
            || terminal
        {
            self.apply_call_control(control)
        } else {
            Ok(())
        };
        self.record_dirty = true;
        self.persist_device_crypto()?;
        outcome
    }

    pub(super) fn holds_call(&self, call_id: &str) -> bool {
        self.call
            .as_ref()
            .is_some_and(|call| call.matches_id(call_id))
    }

    pub(super) fn publish_native_media(
        &mut self,
        call_id: &str,
        signal: crate::native_call::types::Signal,
    ) -> Result<(), PrivateDmRuntimeError> {
        if !signal.bounded()
            || !self
                .call
                .as_ref()
                .is_some_and(|call| call.phase == CallPhase::Active && call.call_id == call_id)
        {
            return Ok(());
        }
        self.publish_authenticated_call(call_id, CallAction::Media(signal))
    }
}

impl PrivateDmRuntime {
    pub(super) fn call_availability(&self) -> Option<contracts::CallAvailability> {
        match self.occupied_calls(now_ms()).len() {
            0 => None,
            1 => Some(contracts::CallAvailability::Busy),
            _ => Some(contracts::CallAvailability::Conflict),
        }
    }
    pub(super) fn occupied_calls(&self, now: u64) -> std::collections::BTreeSet<String> {
        self.sessions
            .values()
            .flat_map(|session| {
                let mut calls = session.call_occupancy.calls(now);
                if let Some(call) = &session.call {
                    calls.insert(call.call_id.clone());
                }
                calls
            })
            .collect()
    }

    pub fn call_start(&mut self, session_id: &str) -> Result<CallStarted, PrivateDmRuntimeError> {
        self.drain_inbound();
        if !self.occupied_calls(now_ms()).is_empty() {
            return Err(PrivateDmRuntimeError::Attachment(
                "another call is already in flight".into(),
            ));
        }
        self.session_mut(session_id)?.call_start()
    }

    pub fn call_accept(
        &mut self,
        session_id: &str,
        call_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_accept(call_id);
        self.sync_call_media();
        outcome
    }

    pub fn call_decline(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_decline(call_id, reason);
        self.sync_call_media();
        self.sessions.persist_tail()?;
        outcome
    }

    pub fn call_end(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_end(call_id, reason);
        self.sync_call_media();
        self.sessions.persist_tail()?;
        outcome
    }
}
