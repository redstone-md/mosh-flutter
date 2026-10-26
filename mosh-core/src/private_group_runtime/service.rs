//! Inbound routing and group protocol service.

use super::*;

impl PrivateGroupRuntime {
    /// One native protocol turn; snapshots and read markers remain UI-owned.
    pub(crate) fn service(&mut self) -> Result<(), PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail()?;
        Ok(())
    }

    pub(super) fn drain_inbound(&mut self) -> Result<(), PrivateGroupError> {
        self.drain_directed_history();
        let inbound = group_inbox().drain();
        for message in inbound {
            let group_id = match channel_group_id(&message.channel) {
                Some(gid) => gid.to_string(),
                None => continue,
            };
            if let Some(session) = self.groups.get_mut(&group_id) {
                // A single bad inbound frame must never abort the drain — it
                // would also fail the caller (send/poll/list drain first). After
                // a restart the in-memory dedup set is empty, so the mesh
                // re-delivers already-consumed MLS messages whose decrypt fails
                // ("secret deleted for forward secrecy"); drop and keep going,
                // mirroring the DM runtime.
                if let Err(error) = session.handle_moss_message(message) {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::FRAME,
                        &group_id,
                        &format!("dropping inbound group frame: {error}"),
                    );
                }
            }
        }
        for session in self.groups.values_mut() {
            if let Err(error) = session.apply_deletions() {
                dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    &session.group_id,
                    &format!("group deletion sync deferred: {error}"),
                );
                continue;
            }
            let _ = session.sync_deletions(now_ms());
            let _ = session.sync_plus(now_ms());
            if let Err(error) = session.sync_history(now_ms()) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &session.group_id,
                    &format!("group history deferred: {error}"),
                );
            }
            session.pump_attachment_requests();
            // ADR 0005: a roster change may legitimize lag-buffered commits.
            session.sync_roster_state();
            if let Err(error) = session.sync_names() {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &session.group_id,
                    &format!("group name sync failed: {error}"),
                );
            }
        }
        Ok(())
    }
}
