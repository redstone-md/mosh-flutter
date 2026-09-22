//! The poll snapshot and the typing roster view.

use super::*;

impl GroupSession {
    pub(super) fn snapshot(&mut self) -> GroupSnapshot {
        GroupSnapshot {
            group_id: self.group_id.clone(),
            mesh_id: self.mesh_id.clone(),
            label: self.label.clone(),
            display_name: self.display_name.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            creator_fingerprint: self.creator_fingerprint.clone(),
            is_admin: self.is_admin,
            state: self.state(),
            member_count: self.crypto.member_count(),
            invite_uri: self.invite_uri.clone(),
            messages: self.messages.to_vec(),
            attachments: self.transfer.views(),
            dm_offers: self.dm_offers.to_vec(),
            mesh: mesh::mesh_info(&self.node),
            needs_rejoin: self.needs_rejoin,
            org_pubkey: self.org_pubkey.clone(),
            member_peer_ids: match self.org_pubkey {
                Some(_) => self.crypto.member_identities(),
                None => Vec::new(),
            },
            typing_members: self.typing_members_view(now_ms()),
            events: mesh::snapshot_events(),
        }
    }

    /// The live typing roster: every entry past its deadline is dropped
    /// first, then the rest read out in fingerprint order (stable for the
    /// poll diff; the deadline travels along). Driven by the poll heartbeat,
    /// so no timer of its own.
    pub(super) fn typing_members_view(&mut self, now: u64) -> Vec<TypingMember> {
        self.typing_members.retain(|_, until| *until > now);
        let mut members: Vec<TypingMember> = self
            .typing_members
            .iter()
            .map(|(fingerprint, until)| TypingMember {
                fingerprint: fingerprint.clone(),
                display_name: self.member_display_name(fingerprint),
                until_ms: *until,
            })
            .collect();
        members.sort_by(|a, b| a.fingerprint.cmp(&b.fingerprint));
        members
    }

    /// The typing roster without expiring: tests read the standing entries.
    #[cfg(test)]
    pub(super) fn typing_members_live(&self) -> Vec<TypingMember> {
        let mut members: Vec<TypingMember> = self
            .typing_members
            .iter()
            .map(|(fingerprint, until)| TypingMember {
                fingerprint: fingerprint.clone(),
                display_name: self.member_display_name(fingerprint),
                until_ms: *until,
            })
            .collect();
        members.sort_by(|a, b| a.fingerprint.cmp(&b.fingerprint));
        members
    }

    /// A member's best-known display name: the name their authenticated
    /// frames carry, else the fingerprint. Kept cheap by construction — the
    /// map only ever holds entries for members that typed or spoke.
    pub(super) fn member_display_name(&self, fingerprint: &str) -> String {
        self.member_names
            .get(fingerprint)
            .cloned()
            .unwrap_or_else(|| fingerprint.to_string())
    }

    pub(super) fn state(&self) -> String {
        if self.joined && self.crypto.is_ready() {
            "ready".to_string()
        } else {
            "waiting".to_string()
        }
    }
}
