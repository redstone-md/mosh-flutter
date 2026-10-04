//! Caller commands for attachments, receipts, snapshots and closure.

use super::*;

impl PrivateDmRuntime {
    /// Signals "I am typing" for one session, driven by the composer's input.
    /// The per-keystroke call is folded down to the refresh cadence inside the
    /// session; a publish the transport refuses is retried on the next call
    /// (no error to the composer — a dropped hint only delays a hint).
    pub fn typing_signal(&mut self, session_id: &str) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        session.publish_typing(now_ms());
        Ok(())
    }

    /// The app-level read-receipts answer, as persisted in the data dir.
    /// Absent file means the default: off.
    pub fn read_receipts_enabled(&self) -> bool {
        crate::read_receipts::load(&crate::api::shared_runtime::resolved_data_dir())
            .is_some_and(|setting| setting.enabled)
    }

    /// Records the app-level read-receipts answer. BOTH values persist: an
    /// off is a decision too, not an absence (the default is off, so only an
    /// explicit on — and an explicit off — must survive a restart).
    pub fn set_read_receipts_enabled(
        &mut self,
        enabled: bool,
    ) -> Result<(), PrivateDmRuntimeError> {
        crate::read_receipts::save(
            &crate::api::shared_runtime::resolved_data_dir(),
            &ReadReceiptsSetting { enabled },
        )
        .map_err(|error| PrivateDmRuntimeError::Moss(error.to_string()))
    }

    /// Reports "the user is looking at this DM": every counterpart message
    /// not yet read gets its ReadReceipt (best-effort, one frame per
    /// message), and each send files the honest `message_read` event. The
    /// api/Dart poll calls this while the conversation screen is open. A
    /// toggle that is off makes this a no-op — no frames, no events — and
    /// by the symmetry rule a user who does not send receipts also ignores
    /// the ones addressed to it.
    pub fn mark_viewed(&mut self, session_id: &str) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        if !self.read_receipts_enabled() {
            return Ok(());
        }
        let session = self.session_mut(session_id)?;
        session.mark_viewed();
        Ok(())
    }

    /// Encrypts a file, stores the sender's own copy, and announces the
    /// manifest to the peer over the MLS-protected control channel.
    pub fn send_attachment(
        &mut self,
        session_id: &str,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        let result = self
            .session_mut(session_id)?
            .send_attachment(file_name, mime, bytes, thumbnail, voice)?;
        if let Err(error) = self.sessions.persist_tail() {
            self.log_persistence_failure(session_id, &error);
        }
        Ok(result)
    }

    /// Begins (or retries) downloading a peer's attachment.
    pub fn download_attachment(
        &mut self,
        session_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        session.transfer.start_download(attachment_id)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        session_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let session = self.session_mut(session_id)?;
        Ok(session.transfer.cancel(attachment_id)?)
    }

    /// Serves a byte range for streaming playback, fetching the region ahead
    /// of the sequential cursor when it has not arrived yet.
    pub fn stream_attachment_range(
        &mut self,
        session_id: &str,
        attachment_id: &str,
        start: u64,
        end: u64,
    ) -> Result<StreamRange, PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        let outcome = session.transfer.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }

    pub fn poll_session(
        &mut self,
        session_id: &str,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        self.drain_inbound();
        Ok(self.session_mut(session_id)?.snapshot())
    }

    pub fn list_sessions(&mut self) -> Result<SessionListSnapshot, PrivateDmRuntimeError> {
        self.drain_inbound();
        let mut snapshots: Vec<SessionSnapshot> = self
            .sessions
            .values_mut()
            .map(PrivateDmSession::snapshot)
            .collect();
        snapshots.sort_by(|a, b| a.session_id.cmp(&b.session_id));
        Ok(SessionListSnapshot {
            sessions: snapshots,
        })
    }

    pub fn close_session(
        &mut self,
        session_id: &str,
    ) -> Result<CloseSessionResult, PrivateDmRuntimeError> {
        match self.sessions.remove(session_id) {
            Some(session) => {
                self.transport.close_room(
                    &session.mesh_id,
                    &session_channels(&session.session_id),
                    &format!("{KIND} {session_id}"),
                );
                // Purge persisted state too, otherwise the conversation
                // re-appears on the next launch via rehydrate.
                self.sessions.forget(session_id);
                if let Some(p) = self.sessions.persistence() {
                    if let Err(error) = p.delete_session(session_id) {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::PERSIST,
                            session_id,
                            &format!("failed to delete persisted session: {error}"),
                        );
                    }
                }
                Ok(CloseSessionResult {
                    session_id: session_id.to_string(),
                    closed: true,
                })
            }
            None => Err(PrivateDmRuntimeError::MissingSession),
        }
    }
}
