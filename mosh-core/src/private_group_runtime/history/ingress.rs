//! Verify every representation against current native permission before queuing it.
use super::protocol::{CheckedFrame, DirectedHistory, GroupBody};
use super::*;
use crate::conversation::recovery::{
    transport,
    wire::{HistoryFrame, HistoryMessage},
    HistorySyncReason,
};
impl GroupSession {
    pub(super) fn drain_history_frames(&mut self) {
        for frame in self.recovery.drain() {
            if let Err(error) = self.receive_history(frame) {
                self.recovery.error = Some(if matches!(error, PrivateGroupError::Persistence(_)) {
                    HistorySyncReason::StorageRefused
                } else {
                    HistorySyncReason::EvidenceMissing
                });
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &self.group_id,
                    &format!("group history: {error}"),
                );
            }
        }
    }
    pub(in crate::private_group_runtime) fn queue_history(
        &mut self,
        frame: HistoryFrame,
        directed: bool,
        carrier: &crate::sender_auth::VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let checked = self.check_history(frame)?;
        if checked.sender.peer_id != carrier.peer_id
            || checked.sender.mls_signer != carrier.mls_signer
        {
            return Err(PrivateGroupError::Codec(
                "history carrier keys differ".into(),
            ));
        }
        if !directed && !matches!(checked.body.message, HistoryMessage::Probe) {
            return Err(PrivateGroupError::Codec(
                "group history content requires directed carrier".into(),
            ));
        }
        self.recovery
            .queue(checked.frame)
            .map_err(PrivateGroupError::Codec)
    }

    pub(super) fn check_history(
        &mut self,
        frame: HistoryFrame,
    ) -> Result<CheckedFrame, PrivateGroupError> {
        let permit = self.history_dispatch.permit();
        let body: GroupBody = frame
            .open_payload(
                &self.deletions.context,
                &self.mesh_id,
                &self.control_channel,
            )
            .map_err(PrivateGroupError::Codec)?;
        if frame.sender_key == self.device_fingerprint
            || frame
                .recipient_key
                .as_ref()
                .is_some_and(|p| p != &self.device_fingerprint)
            || (!matches!(body.message, HistoryMessage::Probe) && frame.recipient_key.is_none())
        {
            return Err(PrivateGroupError::Codec(
                "group history recipient differs".into(),
            ));
        }
        let sender = self.history_carrier_member(&body)?;
        if sender.peer_id != frame.sender_key {
            return Err(PrivateGroupError::Codec(
                "group history member differs".into(),
            ));
        }
        if body.scope.head != self.current_history_head()? && body.evidence.is_none() {
            if body.scope.head.context.epoch > self.crypto.history_context()?.epoch {
                self.request_transition_evidence(&frame, &body.scope)?;
            } else if matches!(body.message, HistoryMessage::Probe) {
                let target = self.current_history_head()?;
                self.answer_transition_evidence(
                    &frame,
                    body.scope.head.context.clone(),
                    target,
                    0,
                )?;
            }
            return Err(PrivateGroupError::NotReady);
        }
        Ok(CheckedFrame {
            frame,
            body,
            sender,
            permit,
        })
    }

    pub(super) fn receive_history(&mut self, frame: HistoryFrame) -> Result<(), PrivateGroupError> {
        let checked = self.check_history(frame)?;
        if checked.body.evidence.is_some() {
            return self.receive_transition_evidence(checked);
        }
        match checked.body.message.clone() {
            HistoryMessage::Probe => self.answer_history(checked, None),
            HistoryMessage::Pull(pull) => self.answer_history(checked, Some(pull)),
            HistoryMessage::Offer {
                manifest,
                total,
                deletion_digest,
            } => {
                if let Some(next) =
                    self.recovery
                        .reoffered(&checked.frame, &manifest, total, &deletion_digest)
                {
                    self.save_history(next, &[], &[], &[])?;
                    self.recovery.last_progress = now_ms();
                    return self.pull_history(now_ms());
                }
                if let Some((next, permit)) = self
                    .recovery
                    .offered(
                        &checked.frame,
                        manifest,
                        total,
                        deletion_digest,
                        &self.device_fingerprint,
                        &self.deletions.context,
                    )
                    .map_err(PrivateGroupError::Codec)?
                {
                    self.save_history(next, &[], &[], &[])?;
                    self.recovery.permit = Some(permit);
                    self.recovery.last_progress = now_ms();
                    self.pull_history(now_ms())?;
                }
                Ok(())
            }
            HistoryMessage::Page {
                manifest,
                total,
                offset,
                records,
                fragment,
            } => self.import_history(&checked, manifest, total, offset, records, fragment),
            HistoryMessage::Journal {
                manifest,
                deletion_digest,
                page,
            } => self.import_history_journal(&checked, manifest, deletion_digest, page),
            HistoryMessage::Unavailable => {
                self.recovery.unavailable(&checked.frame, now_ms());
                Ok(())
            }
        }
    }
}

impl PrivateGroupRuntime {
    pub(in crate::private_group_runtime) fn drain_directed_history(&mut self) {
        for packet in transport::drain() {
            let Ok(directed) = decode_json::<DirectedHistory>(&packet.payload) else {
                continue;
            };
            let Some(session) = self.groups.get_mut(&directed.group_id) else {
                continue;
            };
            let result = (|| {
                let sender = directed
                    .proof
                    .verify(&OrgContext {
                        org_pubkey: session.org_pubkey.as_deref().unwrap_or(""),
                        mesh_id: &session.mesh_id,
                        channel_kind: &session.control_channel,
                    })
                    .map_err(PrivateGroupError::Codec)?;
                let ControlEnvelope::History { group_id, frame } = decode_json(&sender.payload)?
                else {
                    return Err(PrivateGroupError::Codec(
                        "invalid directed group history".into(),
                    ));
                };
                if group_id != session.group_id
                    || frame.sender_key != sender.peer_id
                    || packet.claimed_peer != sender.peer_id
                {
                    return Err(PrivateGroupError::Codec(
                        "directed group carrier differs".into(),
                    ));
                }
                session.queue_history(frame, true, &sender)
            })();
            if let Err(error) = result {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &session.group_id,
                    &format!("dropping directed group history: {error}"),
                );
            }
        }
    }
}
