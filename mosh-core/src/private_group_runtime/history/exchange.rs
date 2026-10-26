//! Only discovery is room-scoped; replies use the shared bounded directed owner.
use super::*;
use super::{
    protocol::{DirectedHistory, GroupBody},
    records::GroupRecord,
};
use crate::conversation::recovery::{
    transport,
    wire::{HistoryFrame, HistoryMessage, HistoryPull},
};
impl GroupSession {
    pub(super) fn pull_history(&mut self, now: u64) -> Result<(), PrivateGroupError> {
        let checkpoint = &self.recovery.checkpoint;
        let Some(source) = checkpoint.source.clone() else {
            return Ok(());
        };
        self.send_history(
            Some(source),
            HistoryMessage::Pull(HistoryPull {
                manifest: checkpoint.progress.manifest.clone().unwrap_or_default(),
                offset: checkpoint.progress.cursor,
                fragment_offset: checkpoint.partial.as_ref().map_or(0, |p| p.offset()),
                deletion_digest: checkpoint.deletion_digest.clone(),
                journal: !checkpoint.journal_complete,
                journal_after: checkpoint.journal_after.clone(),
            }),
        )?;
        self.recovery.last_pull = now;
        Ok(())
    }

    pub(super) fn send_history(
        &mut self,
        recipient: Option<String>,
        message: HistoryMessage<GroupRecord>,
    ) -> Result<(), PrivateGroupError> {
        let permit = self.history_dispatch.permit();
        self.reply_history(
            recipient,
            self.recovery.checkpoint.progress.request_id.clone(),
            self.recovery.checkpoint.round,
            message,
            permit,
        )
    }

    pub(super) fn reply_history(
        &mut self,
        recipient: Option<String>,
        request_id: String,
        round: u64,
        message: HistoryMessage<GroupRecord>,
        permit: transport::DispatchPermit,
    ) -> Result<(), PrivateGroupError> {
        let scope = self.own_history_scope()?;
        let partial_digest = matches!(&message, HistoryMessage::Pull(pull) if !pull.journal)
            .then(|| {
                self.recovery
                    .checkpoint
                    .partial
                    .as_ref()
                    .map(|partial| partial.digest().to_string())
            })
            .flatten();
        self.dispatch_history_body(
            recipient,
            request_id,
            round,
            GroupBody {
                scope,
                message,
                evidence: None,
                partial_digest,
                erased_fragment: false,
            },
            permit,
        )
    }

    pub(super) fn dispatch_history_body(
        &mut self,
        recipient: Option<String>,
        request_id: String,
        round: u64,
        body: GroupBody,
        permit: transport::DispatchPermit,
    ) -> Result<(), PrivateGroupError> {
        let mut frame = HistoryFrame {
            version: 1,
            conversation: self.deletions.context.clone(),
            mesh_id: self.mesh_id.clone(),
            channel: self.control_channel.clone(),
            sender_key: String::new(),
            recipient_key: recipient.clone(),
            request_id,
            round,
            payload_b64: String::new(),
            signature: String::new(),
        };
        frame
            .seal_payload(
                self.node
                    .identity_signer()
                    .map_err(|e| PrivateGroupError::Moss(e.to_string()))?,
                &body,
            )
            .map_err(PrivateGroupError::Codec)?;
        let envelope = ControlEnvelope::History {
            group_id: self.group_id.clone(),
            frame,
        };
        if let Some(recipient) = recipient {
            let proof = self.sign_application(&envelope, &self.control_channel)?;
            let bytes = serde_json::to_vec(&DirectedHistory {
                group_id: self.group_id.clone(),
                proof,
            })
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
            transport::enqueue(self.node.clone(), recipient, bytes, permit)
                .map_err(PrivateGroupError::Codec)
        } else {
            self.publish_control(&envelope)
        }
    }
}
