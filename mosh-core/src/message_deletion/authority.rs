use super::{
    protocol::DeleteRequest, shared::DeletionActor, DeletionRecord, DeletionStatus, MessageOrigin,
};
use std::collections::{BTreeMap, BTreeSet};

/// A verified snapshot of the conversation owner's current membership/roles.
pub(crate) struct DeletionAuthority {
    pub local: DeletionActor,
    pub members: BTreeSet<String>,
    pub admins: BTreeSet<String>,
    pub accepted: BTreeSet<String>,
    pub accounts: BTreeMap<String, String>,
    pub public_channel: bool,
}

impl DeletionAuthority {
    pub fn member(&self, key: &str) -> bool {
        self.public_channel || self.members.contains(key)
    }

    pub fn same_account(&self, left: &str, right: &str) -> bool {
        left == right
            || self
                .accounts
                .get(left)
                .is_some_and(|a| self.accounts.get(right) == Some(a))
    }

    pub fn permitted(&self, origin: &MessageOrigin) -> Option<bool> {
        if !self.member(&self.local.key) {
            return None;
        }
        if self.same_account(&self.local.key, &origin.author)
            || super::ownership::same_account(
                &self.local.key,
                self.local.ownership.as_deref(),
                &origin.author,
                origin.ownership.as_deref(),
            )
        {
            return Some(false);
        }
        self.admins.contains(&self.local.key).then_some(true)
    }

    pub fn may_ack(&self, request: &DeleteRequest, key: &str) -> bool {
        self.may_ack_with_proof(
            request,
            key,
            (key == self.local.key)
                .then_some(self.local.ownership.as_deref())
                .flatten(),
        )
    }

    pub fn may_ack_with_proof(
        &self,
        request: &DeleteRequest,
        key: &str,
        proof: Option<&str>,
    ) -> bool {
        self.member(key)
            && (request.ownership.is_none() || proof.is_some())
            && !self.same_account(key, &request.actor)
            && !super::ownership::same_account(
                key,
                proof,
                &request.actor,
                request.ownership.as_deref(),
            )
    }

    pub fn validate(&self, record: &DeletionRecord, carrier: &str) -> Result<(), String> {
        if !self.member(carrier) {
            return Err("deletion carrier is not a member".into());
        }
        let request = record.request.as_ref().ok_or("missing deletion request")?;
        let confirmed = record.status == DeletionStatus::Confirmed;
        if confirmed && self.accepted.contains(&request.digest()?) {
            return Ok(());
        }
        let endorsed = confirmed
            && (self.admins.contains(carrier)
                || record.acknowledgement.as_ref().is_some_and(|ack| {
                    self.admins.contains(&ack.actor)
                        && self.may_ack_with_proof(request, &ack.actor, ack.ownership.as_deref())
                }));
        if request.epoch > self.local.epoch || (!self.member(&request.actor) && !endorsed) {
            return Err("deletion author left or epoch is ahead".into());
        }
        let authorized = if request.moderated {
            self.admins.contains(&request.actor) || endorsed
        } else {
            self.same_account(&request.actor, &request.target.author)
                || super::ownership::same_account(
                    &request.actor,
                    request.ownership.as_deref(),
                    &request.target.author,
                    request.target.ownership.as_deref(),
                )
        };
        if !authorized {
            return Err("deletion permission denied".into());
        }
        if let Some(ack) = &record.acknowledgement {
            if !(self.may_ack_with_proof(request, &ack.actor, ack.ownership.as_deref()) || endorsed)
            {
                return Err("ineligible deletion acknowledgement".into());
            }
        }
        Ok(())
    }
}
