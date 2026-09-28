mod bootstrap;
mod delivery;
mod evidence;
mod recovery;
mod transition;

use super::{invalid, proof::IdentityClaim, runtime::send_packet, types::*};
use crate::device_link::{identity::DeviceIdentity, roster::DeviceRoster, types::DeviceDescriptor};
use crate::private_dm_runtime::{
    contracts::DmDeviceRevocationState, PrivateDmRuntime, PrivateDmSession,
};
pub(super) use evidence::{RemovalJournal, RemovalRecord};

impl DeviceMembership {
    pub(super) fn authorize_current_admission(
        &self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        sender_roster: &DeviceRoster,
        claim: &IdentityClaim,
    ) -> Result<()> {
        if self.revoked
            || identity.revoked().map_err(|_| invalid())?
            || !self.authorized(sender, &sender_roster.user_id())
        {
            return Err(invalid());
        }
        let own =
            (identity.roster().user_id() == claim.roster.user_id()).then_some(identity.roster());
        for current in [
            Some(sender_roster),
            self.current_roster(&claim.roster.user_id()),
            own,
        ]
        .into_iter()
        .flatten()
        {
            if current.extends(&claim.roster).map_err(|_| invalid())? {
                if !current
                    .authorizes_admitted(&claim.roster, &claim.device()?)
                    .map_err(|_| invalid())?
                {
                    return Err(invalid());
                }
            } else if !claim.roster.extends(current).map_err(|_| invalid())? {
                return Err(invalid());
            }
        }
        Ok(())
    }

    pub(super) fn pin_roster(&mut self, roster: &DeviceRoster) -> Result<()> {
        if let Some(current) = self.current_roster(&roster.user_id()) {
            if current.extends(roster).map_err(|_| invalid())? {
                return Ok(());
            }
            if !roster.extends(current).map_err(|_| invalid())? {
                return Err(invalid());
            }
        }
        self.pending_rosters
            .retain(|r| r.user_id() != roster.user_id());
        self.pending_rosters.push(roster.clone());
        Ok(())
    }

    pub(super) fn observe_roster_removal(&mut self, roster: &DeviceRoster) -> Result<bool> {
        let removes_client = self
            .topology
            .roster(&roster.user_id())
            .is_some_and(|base| roster.has_removal_since(base).unwrap_or(false))
            || self.topology.clients.iter().any(|c| {
                c.roster.user_id() == roster.user_id()
                    && roster
                        .revoked_since(&c.roster, &c.device_id)
                        .unwrap_or(false)
            });
        if removes_client {
            self.pin_roster(roster)?
        }
        Ok(removes_client)
    }

    pub(crate) fn removal_pending(&self, target: &str, roster: &DeviceRoster) -> bool {
        self.topology.clients.iter().any(|client| {
            client.device_id == target
                && roster
                    .revoked_since(&client.roster, target)
                    .unwrap_or(false)
        }) || self
            .removals
            .iter()
            .any(|journal| journal.evidence.target == target && !journal.waiting.is_empty())
    }

    pub(super) fn current_roster(&self, user: &str) -> Option<&DeviceRoster> {
        let current = self.topology.roster(user);
        match self.pending_rosters.iter().find(|r| r.user_id() == user) {
            Some(pending) if current.is_none_or(|r| pending.extends(r).unwrap_or(false)) => {
                Some(pending)
            }
            _ => current,
        }
    }

    pub(super) fn authorized(&self, device: &DeviceDescriptor, user: &str) -> bool {
        !self.revoked
            && self.current_roster(user).is_some_and(|r| {
                match self
                    .topology
                    .clients
                    .iter()
                    .find(|c| c.device_id == device.device_id)
                {
                    Some(c) => r.authorizes_admitted(&c.roster, device).unwrap_or(false),
                    None => r.devices().is_ok_and(|devices| devices.contains(device)),
                }
            })
    }

    pub(super) fn pending_removal(&self) -> bool {
        self.topology.clients.iter().any(|client| {
            client
                .device()
                .is_ok_and(|d| !self.authorized(&d, &client.roster.user_id()))
        })
    }
}

impl PrivateDmSession {
    pub(in crate::private_dm_runtime::devices) fn awaiting_device_epoch(&self) -> bool {
        self.membership.as_ref().is_some_and(|membership| {
            membership.pending_removal()
                || membership.recovery.as_ref().is_some_and(|recovery| {
                    self.crypto
                        .epoch()
                        .is_none_or(|epoch| epoch < recovery.required_epoch)
                })
        })
    }

    pub(in crate::private_dm_runtime) fn device_revocation_state(
        &self,
    ) -> Option<DmDeviceRevocationState> {
        let membership = self.membership.as_ref()?;
        if membership.revoked {
            return Some(DmDeviceRevocationState::Revoked);
        }
        if membership.pending_removal() || membership.removals.iter().any(|r| !r.waiting.is_empty())
        {
            return Some(DmDeviceRevocationState::Pending);
        }
        (!membership.removals.is_empty()).then_some(DmDeviceRevocationState::Applied)
    }

    pub(in crate::private_dm_runtime) fn ensure_device_authorized(&self) -> Result<()> {
        if self.membership.as_ref().is_some_and(|m| m.revoked) {
            return Err(crate::private_dm_runtime::PrivateDmRuntimeError::Revoked);
        }
        Ok(())
    }
}

impl PrivateDmRuntime {
    fn adopt_own_removal(&self, evidence: &RemovalRecord) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let peer = self.transport.local_peer_id().ok_or_else(invalid)?;
        let mut identity = DeviceIdentity::open(store, &peer).map_err(|_| invalid())?;
        if evidence.roster.user_id() != identity.roster().user_id()
            || identity
                .roster()
                .extends(&evidence.roster)
                .map_err(|_| invalid())?
        {
            return Ok(());
        }
        identity
            .adopt_roster(evidence.roster.clone())
            .map_err(|_| invalid())
    }
}
