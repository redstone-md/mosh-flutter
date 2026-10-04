//! MLS self-removal and release of the group room.

use super::*;

#[cfg(test)]
#[path = "org_acceptance_durability_tests.rs"]
mod org_acceptance_durability_tests;

impl PrivateGroupRuntime {
    pub(crate) fn group_signer_public(
        &mut self,
        group_id: &str,
    ) -> Result<Vec<u8>, PrivateGroupError> {
        Ok(self.group_mut(group_id)?.crypto.signer_public())
    }

    pub fn close(&mut self, group_id: &str) -> Result<GroupLeaveResult, PrivateGroupError> {
        let session = self.group_mut(group_id)?;

        if session.joined {
            let own_fp = session.crypto.fingerprint();
            // Everyone leaves the same way: MLS forbids committing your own
            // removal, so a self-Remove proposal goes out and a member who
            // stays commits it. For an ordinary member that is the admin; for
            // the admin it is the successor (`should_commit_departure`).
            let proposal_bytes = session.crypto.leave_proposal_bytes()?;
            let envelope = ControlEnvelope::SelfRemove {
                group_id: session.group_id.clone(),
                from_fingerprint: own_fp.clone(),
                proposal_b64: encode(&proposal_bytes),
            };
            session.publish_control(&envelope)?;
            if session.is_admin {
                // Compatibility only. Clients that predate the tree-derived
                // successor still need to be told who takes over; newer ones
                // ignore this frame and read the commit instead.
                if let Some(next_admin) =
                    successor_of(session.crypto.member_fingerprints(), &own_fp)
                {
                    let handoff = ControlEnvelope::AdminHandoff {
                        group_id: session.group_id.clone(),
                        from_fingerprint: own_fp,
                        next_admin_fingerprint: next_admin,
                    };
                    session.publish_control(&handoff)?;
                }
            }
        }

        self.discard_local_group(group_id);
        Ok(GroupLeaveResult {
            group_id: group_id.to_string(),
            closed: true,
        })
    }

    /// Roll back a newly opened local group without a fallible departure publish.
    pub(crate) fn discard_local_group(&mut self, group_id: &str) {
        if let Some(session) = self.groups.remove(group_id) {
            runtime::close_room(
                &self.shared_node,
                &session.node,
                &session.mesh_id,
                &group_channels(group_id),
                &format!("{KIND} {group_id}"),
            );
        }
        self.groups.forget(group_id);
        if let Some(p) = self.groups.persistence() {
            if let Err(error) = p.delete_group(group_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    group_id,
                    &format!("failed to delete persisted group: {error}"),
                );
            }
        }
    }
}
