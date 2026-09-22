//! Outbound shape and inbound message handling.

use super::*;

impl ChannelSession {
    pub(super) fn publishable_message(&self, message: &ChannelMessage) -> ChannelMessage {
        let mut publishable = message.clone();
        publishable.delivery_status = None;
        publishable.delivery_error = None;
        publishable.retryable = None;
        publishable.retry_count = None;
        publishable
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    pub(super) fn outbox(&mut self) -> Outbox<'_, ChannelMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    pub(super) fn handle_message(
        &mut self,
        message: MossReceivedMessage,
    ) -> Result<(), ChannelRuntimeError> {
        if self.seen.seen_before(&message.channel, &message.payload) {
            return Ok(());
        }
        if message.channel == self.topic {
            let envelope: ChannelMessage = serde_json::from_slice(&message.payload)
                .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
            if self.messages.holds_copy_of(&envelope) {
                return Ok(());
            }
            if envelope.from_fingerprint == self.device_fingerprint {
                return Ok(());
            }
            self.messages.push_stamped(envelope);
            Ok(())
        } else if message.channel == self.blob_topic {
            self.handle_blob(message.payload)
        } else {
            Ok(())
        }
    }

    // Blob traffic stays on the room wire (spec #8, this slice): a channel
    // has no single direct peer to stream to, and the stream carrier is the
    // DM fast path only. The chunk protocol below is unchanged.
}
