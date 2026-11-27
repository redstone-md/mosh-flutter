//! The roster-lag buffer: commits from an author a newer roster promotes.

use super::*;

impl GroupSession {
    /// Hold a commit until the roster that promotes its author lands. The
    /// envelope signature proves only a key, and keys are free, so the slot
    /// goes to a key that already holds a leaf in this group: only a member
    /// can be the admin a newer roster promotes. Each member gets a few
    /// slots, so one member's flood cannot push out another's commit.
    pub(super) fn buffer_roster_lagged(&mut self, entry: RosterLaggedCommit) {
        let sender = entry.sender_peer_id.as_str();
        // Control frames skip the replay set; a redelivery is already held.
        if self
            .roster_lag
            .iter()
            .any(|held| held.sender_peer_id == sender && held.commit_b64 == entry.commit_b64)
        {
            return;
        }
        let held = self
            .roster_lag
            .iter()
            .filter(|held| held.sender_peer_id == sender)
            .count();
        if held >= ROSTER_LAG_PER_SENDER
            || !self
                .crypto
                .member_identities()
                .iter()
                .any(|id| id == sender)
        {
            dlog::write(
                LogLevel::Warn,
                kinds::COMMIT,
                &self.group_id,
                &format!("lagged commit from {sender} not buffered"),
            );
            return;
        }
        // FIFO at cap: garbage must not lock out a later genuine entry.
        if self.roster_lag.len() >= ROSTER_LAG_CAP {
            self.roster_lag.remove(0);
        }
        self.roster_lag.push(entry);
    }

    /// Re-run lag-buffered commits after a roster change. Entries whose
    /// author became admin apply; entries still ahead of our roster stay;
    /// entries whose claimed version we now have (author still not admin)
    /// drop for good.
    pub(super) fn retry_roster_lagged(&mut self) {
        if self.roster_lag.is_empty() {
            return;
        }
        let mine = self.own_roster_version();
        let pending = std::mem::take(&mut self.roster_lag);
        for entry in pending {
            if self.roster_role_is_admin(&entry.sender_peer_id) {
                if let Err(error) = self.apply_commit_sequenced(entry.commit_b64) {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::COMMIT,
                        &self.group_id,
                        &format!("lagged commit apply failed: {error}"),
                    );
                }
            } else if Some(entry.roster_version) > mine {
                self.roster_lag.push(entry);
            }
        }
    }
}
