//! Inbound routing and group protocol service.

use super::*;

impl PrivateGroupRuntime {
    pub(super) fn drain_inbound(&mut self) -> Result<(), PrivateGroupError> {
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
            session.apply_deletions()?;
            let _ = session.sync_deletions(now_ms());
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
