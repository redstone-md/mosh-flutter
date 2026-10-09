use super::{protocol::CallControl, *};

impl PrivateDmSession {
    pub(super) fn apply_call_control(
        &mut self,
        control: CallControl,
    ) -> Result<(), PrivateDmRuntimeError> {
        let own = hex::encode(self.crypto.signer_public());
        if self.call_controls.confirmed_closed(&control.call_id) {
            return Ok(());
        }
        if control.signer == own {
            return Ok(());
        }
        if self
            .membership
            .as_ref()
            .is_some_and(|membership| membership.call_own(&control.signer))
        {
            self.observe_own_call(&control);
            return Ok(());
        }
        match &control.action {
            CallAction::Media(signal) => {
                self.receive_native_media(&control, signal.clone());
                Ok(())
            }
            CallAction::Offer {
                key_b64,
                nonce_prefix_b64,
                native,
            } => {
                if *native != protocol::native_platform() {
                    return Ok(());
                }
                self.receive_call_offer(&control, key_b64, nonce_prefix_b64)
            }
            CallAction::Answer => self.receive_call_answer(&control),
            CallAction::Occupied { .. } => Ok(()),
            CallAction::Selected { receiver } => {
                self.receive_call_selection(&control, receiver, &own)
            }
            CallAction::Decline { .. } | CallAction::End { .. } => {
                self.receive_call_termination(&control)
            }
        }
    }

    fn receive_native_media(
        &mut self,
        control: &CallControl,
        signal: crate::native_call::types::Signal,
    ) {
        if !signal.bounded() {
            return;
        }
        let Some(call) = self
            .call
            .as_mut()
            .filter(|call| call.phase == CallPhase::Active && call.call_id == control.call_id)
        else {
            return;
        };
        let remote = if call.direction == crate::voice_call_runtime::CallDirection::Caller {
            call.selected_signer.as_deref()
        } else {
            Some(call.caller_signer.as_str())
        };
        if remote != Some(&control.signer) || call.remote_peer != control.peer {
            return;
        }
        if let crate::native_call::types::Signal::Description(description) = &signal {
            let binding = &description.binding;
            if binding.session_id != self.session_id
                || binding.call_id != call.call_id
                || binding.caller != call.caller_signer
                || call.selected_signer.as_ref() != Some(&binding.callee)
                || description.offer
                    != (call.direction == crate::voice_call_runtime::CallDirection::Callee)
            {
                return;
            }
        }
        if matches!(signal, crate::native_call::types::Signal::Camera { .. }) {
            if control.sequence <= call.native_camera_sequence {
                return;
            }
            call.native_camera_sequence = control.sequence;
        }
        if call.native_controls.len() >= 16 {
            call.native_controls.pop_front();
        }
        call.native_controls.push_back(signal);
    }

    fn receive_call_answer(&mut self, control: &CallControl) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self
            .call
            .as_ref()
            .filter(|call| call.call_id == control.call_id)
        else {
            return Ok(());
        };
        if call.direction != crate::voice_call_runtime::CallDirection::Caller {
            return Ok(());
        }
        if call.phase == CallPhase::Active {
            if let Some(receiver) = call.selected_signer.clone() {
                return self.publish_authenticated_call(
                    &control.call_id,
                    CallAction::Selected { receiver },
                );
            }
            return Ok(());
        }
        if call.phase != CallPhase::Outgoing {
            return Ok(());
        }
        self.publish_authenticated_call(
            &control.call_id,
            CallAction::Selected {
                receiver: control.signer.clone(),
            },
        )?;
        let call = self.call.as_mut().expect("call remains installed");
        call.selected_signer = Some(control.signer.clone());
        call.remote_peer = control.peer.clone();
        call.remote_device = control.name.clone();
        call.become_active(now_ms());
        self.note_authenticated_frame(&control.name);
        Ok(())
    }

    fn receive_call_selection(
        &mut self,
        control: &CallControl,
        receiver: &str,
        own: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if self.call.is_none() {
            self.observe_call_selection(control, receiver);
        }
        let Some(call) = self
            .call
            .as_ref()
            .filter(|call| call.call_id == control.call_id)
        else {
            return Ok(());
        };
        if call.caller_signer != control.signer
            || call.direction != crate::voice_call_runtime::CallDirection::Callee
        {
            return Ok(());
        }
        if call.phase == CallPhase::Active {
            return Ok(());
        }
        if receiver != own {
            self.observe_call_selection(control, receiver);
            self.call = None;
            let _ = self
                .transport
                .unsubscribe(&self.mesh_id, &voice_call_channel(&control.call_id));
            return Ok(());
        }
        if call.phase != CallPhase::Accepting {
            return Ok(());
        }
        let call = self.call.as_mut().expect("call remains installed");
        call.selected_signer = Some(receiver.into());
        call.become_active(now_ms());
        self.note_authenticated_frame(&control.name);
        Ok(())
    }

    fn receive_call_termination(
        &mut self,
        control: &CallControl,
    ) -> Result<(), PrivateDmRuntimeError> {
        let authoritative = self.authoritative_call_end(control);
        self.call_occupancy
            .receive_end(&control.signer, &control.call_id);
        let Some(call) = self
            .call
            .as_ref()
            .filter(|call| call.matches_id(&control.call_id))
        else {
            if authoritative {
                self.call_controls.close(&control.call_id, true);
            }
            return Ok(());
        };
        let permitted = if call.phase == CallPhase::Active {
            control.signer == call.caller_signer
                || call.selected_signer.as_ref() == Some(&control.signer)
        } else {
            call.direction == crate::voice_call_runtime::CallDirection::Caller
                || control.signer == call.caller_signer
        };
        if !permitted {
            return Ok(());
        }
        let (kind, duration) = (call.end_kind(), call.duration_ms(now_ms()));
        let caller = call.direction == crate::voice_call_runtime::CallDirection::Caller;
        let call_id = call.call_id.clone();
        let caller_signer = call.caller_signer.clone();
        self.call_controls.close(&call_id, true);
        if caller {
            let action = CallAction::End {
                caller: caller_signer,
                reason: "ended".into(),
            };
            self.call_ends.remember(&call_id, action.clone(), now_ms());
            let _ = self.publish_authenticated_call(&call_id, action);
        }
        self.finish_call(kind, duration);
        Ok(())
    }
}
