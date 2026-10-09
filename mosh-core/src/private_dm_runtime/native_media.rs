use super::*;
use crate::native_call::{
    types::{Choices, Context},
    Hub,
};
use crate::voice_call_runtime::CallDirection;

impl PrivateDmRuntime {
    pub(crate) fn prepare_native_call(
        &mut self,
        session: &str,
        call: &str,
        choices: Choices,
    ) -> Result<Arc<Hub>, String> {
        self.drain_inbound();
        let context = self
            .sessions
            .get(session)
            .and_then(PrivateDmSession::native_context)
            .filter(|context| context.matches(session, call))
            .ok_or("call no longer exists")?;
        let hub = match &self.native_media {
            Some(hub) => hub.clone(),
            None => {
                let hub = Hub::new(self.transport.clone())?;
                self.native_media = Some(hub.clone());
                hub
            }
        };
        hub.prepare(context, choices)?;
        self.sync_native_media();
        Ok(hub)
    }

    pub(super) fn reconcile_call_authority(&mut self) {
        for session in self.sessions.values_mut() {
            if session.call.is_some() && !session.call_authorized() {
                let duration = session
                    .call
                    .as_ref()
                    .map_or(0, |call| call.duration_ms(now_ms()));
                session.finish_call("ended", duration);
            }
        }
    }

    pub(super) fn sync_native_media(&mut self) {
        let Some(hub) = self.native_media.clone() else {
            return;
        };
        let context = self
            .sessions
            .values()
            .find_map(PrivateDmSession::native_context);
        let inbound = context
            .as_ref()
            .and_then(|context| self.sessions.get_mut(&context.session_id))
            .and_then(|session| session.call.as_mut())
            .map(|call| call.native_controls.drain(..).collect())
            .unwrap_or_default();
        hub.sync(context, inbound);
    }

    pub(super) fn pump_native_media(&mut self) {
        let Some(hub) = self.native_media.clone() else {
            return;
        };
        for (session, call, signal) in hub.outbound() {
            if let Some(session) = self.sessions.get_mut(&session) {
                let _ = session.publish_native_media(&call, signal);
            }
        }
        let failed = self
            .sessions
            .values()
            .filter_map(PrivateDmSession::native_context)
            .find(|context| {
                hub.snapshot(&context.session_id, &context.call_id)
                    .is_some_and(|snapshot| snapshot.failed)
            });
        if let Some(context) = failed {
            self.end_failed_native_call(&context.session_id, &context.call_id);
        }
    }

    pub(super) fn end_failed_native_call(&mut self, session_id: &str, call_id: &str) {
        if let Some(session) = self.sessions.get_mut(session_id) {
            let _ = session.call_end(call_id, "connection_lost");
        }
        if let Err(error) = self.sessions.persist_tail() {
            self.log_persistence_failure(KIND, &error);
        }
        self.sync_call_media();
    }
}

impl PrivateDmSession {
    fn call_authorized(&self) -> bool {
        let Some(call) = &self.call else {
            return true;
        };
        if self.ensure_device_authorized().is_err() {
            return false;
        }
        if call.caller_signer.is_empty() {
            return true;
        }
        let signers = self.crypto.member_signers();
        if !signers.contains(&call.caller_signer)
            || call
                .selected_signer
                .as_ref()
                .is_some_and(|selected| !signers.contains(selected))
        {
            return false;
        }
        let Some(membership) = &self.membership else {
            return true;
        };
        if membership
            .call_peer(&hex::encode(self.crypto.signer_public()))
            .is_none()
            || membership.call_peer(&call.caller_signer).is_none()
            || call
                .selected_signer
                .as_ref()
                .is_some_and(|selected| membership.call_peer(selected).is_none())
        {
            return false;
        }
        let remote = if call.direction == CallDirection::Caller {
            call.selected_signer.as_deref()
        } else {
            Some(call.caller_signer.as_str())
        };
        remote
            .is_none_or(|signer| membership.call_peer(signer).as_deref() == Some(&call.remote_peer))
    }

    pub(super) fn native_context(&self) -> Option<Context> {
        if !self.call_authorized() {
            return None;
        }
        let call = self.call.as_ref()?;
        Some(Context {
            session_id: self.session_id.clone(),
            call_id: call.call_id.clone(),
            superseded: call.merged_call_id.clone(),
            active: call.phase == CallPhase::Active,
            caller: call.direction == CallDirection::Caller,
            caller_signer: call.caller_signer.clone(),
            callee_signer: call.selected_signer.clone(),
            peer: call.remote_peer.clone(),
        })
    }
}
