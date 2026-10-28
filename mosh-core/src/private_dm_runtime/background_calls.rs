//! Native call truth feeds the app owner without UI polling or media capture.
use super::*;
use crate::api::background::{BackgroundCallActionOutcome as Outcome, BackgroundCallActionResult};
use crate::api::conversation::{BridgeConversationKind, BridgeConversationRef};
use crate::persistence::background_calls::{
    BackgroundCallAction as Action, BackgroundCallPhase as Phase, BackgroundCallState,
};

impl PrivateDmRuntime {
    pub(super) fn sync_background_calls(&mut self) -> Result<(), String> {
        let Some(store) = self.sessions.persistence() else {
            return Ok(());
        };
        let current: Vec<_> = self.sessions.values().filter_map(call_state).collect();
        if self.background_calls.as_ref() == Some(&current) {
            return Ok(());
        }
        store
            .sync_background_calls(crate::api::background::call_owner_nonce(), &current)
            .map_err(|error| error.to_string())?;
        self.background_calls = Some(current);
        Ok(())
    }

    pub(crate) fn apply_background_call_action(
        &mut self,
        capability: &str,
    ) -> Result<BackgroundCallActionResult, String> {
        self.drain_inbound();
        self.sessions
            .persist_tail()
            .map_err(|error| error.to_string())?;
        self.sync_background_calls()?;
        let Some((current, action)) = self.resolve_background_action(capability)? else {
            return Ok(BackgroundCallActionResult::no(Outcome::Stale));
        };
        let session = self
            .sessions
            .get_mut(&current.session_id)
            .expect("validated current session");
        let outcome = match action {
            Action::Answer => Ok(()), // Visible presentation obtains grants before native acceptance.
            Action::Decline => session.call_decline(&current.call_id, "user_declined"),
            Action::Hangup => session.call_end(&current.call_id, "user_hangup"),
        };
        self.sync_call_media();
        self.sessions
            .persist_tail()
            .map_err(|error| error.to_string())?;
        self.sync_background_calls()?;
        outcome.map_err(|error| error.to_string())?;
        Ok(BackgroundCallActionResult {
            outcome: Outcome::Applied,
            action: Some(action),
            target: Some(BridgeConversationRef {
                kind: BridgeConversationKind::Dm,
                id: current.session_id,
            }),
            call_id: Some(current.call_id),
        })
    }

    fn resolve_background_action(
        &mut self,
        capability: &str,
    ) -> Result<Option<(BackgroundCallState, Action)>, String> {
        let store = self
            .sessions
            .persistence()
            .cloned()
            .ok_or("background storage unavailable")?;
        let owner = crate::api::background::call_owner_nonce();
        let Some(issued) = store
            .background_call_for_capability(capability, owner)
            .map_err(|e| e.to_string())?
        else {
            return Ok(None);
        };
        let Some(session) = self.sessions.get_mut(&issued.session_id) else {
            return Ok(None);
        };
        if session.ensure_device_authorized().is_err() {
            return Ok(None);
        }
        let Some(current) = call_state(session) else {
            return Ok(None);
        };
        let action = store
            .take_background_call_action(capability, owner, &current, now_ms())
            .map_err(|e| e.to_string())?;
        Ok(action.map(|action| (current, action)))
    }
}

fn call_state(session: &PrivateDmSession) -> Option<BackgroundCallState> {
    let call = session.call.as_ref()?;
    let phase = match call.phase {
        CallPhase::Outgoing => Phase::Outgoing,
        CallPhase::Ringing => Phase::Incoming,
        CallPhase::Accepting => Phase::Accepting,
        CallPhase::Active => Phase::Active,
    };
    Some(BackgroundCallState {
        session_id: session.session_id.clone(),
        call_id: call.call_id.clone(),
        phase,
        expires_at_ms: if phase == Phase::Active {
            0
        } else {
            call.offer_first_ms.saturating_add(CALL_RING_TIMEOUT_MS)
        },
        sender: call.remote_device.clone(),
        binding: format!(
            "{}\0{}\0{}",
            call.caller_signer,
            call.selected_signer.as_deref().unwrap_or_default(),
            call.direction.as_str()
        ),
    })
}
