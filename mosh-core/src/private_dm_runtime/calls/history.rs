use super::*;

impl PrivateDmSession {
    pub(in crate::private_dm_runtime) fn finish_call(&mut self, kind: &str, duration_ms: u64) {
        let Some(call) = self.call.take() else {
            return;
        };
        let confirmed = call.direction == crate::voice_call_runtime::CallDirection::Caller
            || call.phase == CallPhase::Active
            || self.call_controls.confirmed_closed(&call.call_id);
        self.call_controls.close(&call.call_id, confirmed);
        if let Some(id) = &call.merged_call_id {
            self.call_controls.close(id, confirmed);
        }
        self.record_dirty = true;
        self.call_occupancy.finish(&call.call_id, confirmed);
        let _ = self
            .transport
            .unsubscribe(&self.mesh_id, &voice_call_channel(&call.call_id));
        self.append_call_event_message(&call.remote_device, kind, duration_ms, &call.call_id);
    }

    pub(super) fn append_call_event_message(
        &mut self,
        remote_device: &str,
        kind: &str,
        duration_ms: u64,
        call_id: &str,
    ) {
        let message = self.messages.stamp(ChatMessage {
            metadata: None,
            from_device: remote_device.into(),
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: None,
            call_event: Some(CallEvent {
                kind: kind.into(),
                duration_ms,
                call_id: call_id.into(),
            }),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        });
        self.messages.push(message);
    }
}
