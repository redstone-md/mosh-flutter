use super::super::*;
use super::{invalid, types::DmOffer};
use crate::device_link::identity::DeviceIdentity;

impl PrivateDmRuntime {
    pub(super) fn can_rejoin_device(
        &self,
        identity: &DeviceIdentity,
        offer: &DmOffer,
    ) -> Result<bool, PrivateDmRuntimeError> {
        let previous = self.session_ref(&offer.session_id)?;
        let Some(membership) = &previous.membership else {
            return Ok(false);
        };
        if !membership.revoked || identity.revoked().map_err(|_| invalid())? {
            return Ok(false);
        }
        if offer.topology.own_user_id != membership.topology.own_user_id
            || offer.group_id != previous.crypto.group_id_bytes().ok_or_else(invalid)?
            || offer.mesh_id != previous.mesh_id
            || offer.fingerprint != previous.fingerprint
        {
            return Err(invalid());
        }
        Ok(true)
    }

    pub(super) fn restore_revoked_history(
        &mut self,
        session: &mut PrivateDmSession,
    ) -> Result<(), PrivateDmRuntimeError> {
        if !self.sessions.holds(&session.session_id) {
            return Ok(());
        }
        let previous = self.session_ref(&session.session_id)?;
        if !previous.membership.as_ref().is_some_and(|m| m.revoked) {
            return Err(invalid());
        }
        let record = previous.to_persisted_record();
        self.sessions.persist_tail()?;
        session.device_id = record.display_name;
        session.participant_id = record.participant_id;
        session.peer_read_ids = record.read_message_ids;
        session.call_controls = record.call_controls;
        self.sessions.replay(
            &session.session_id,
            Restore {
                log: &mut session.messages,
                attempts: &mut session.outbound_attempts,
                transfer: &mut session.transfer,
                local_author: &session.device_id,
            },
        );
        Ok(())
    }
}
