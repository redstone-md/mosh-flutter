//! A recipient-specific manifest omits proven prejoin rows, never missing evidence.
use super::*;
use crate::conversation::recovery::manifest::HistoryKey;

impl GroupSession {
    pub(super) fn eligible_history_key(
        &self,
        row: &StoredMessage<GroupMessage>,
        recipient: &super::protocol::GroupScope,
    ) -> Result<Option<HistoryKey>, String> {
        let key = super::records::GroupRecord::key(row, &self.deletions.context, &self.mesh_id)?;
        let Some(key) = key else {
            return Ok(None);
        };
        let accepted = self
            .persistence
            .as_ref()
            .ok_or("group persistence unavailable")?
            .group_history_evidence::<NativeAcceptance>(&native_acceptance_key(
                &self.group_id,
                &row.message_id,
            ))
            .map_err(|e| e.to_string())?
            .ok_or("group acceptance evidence unavailable")?;
        if recipient
            .entitled_at(self, &accepted.context)
            .map_err(|e| e.to_string())?
            .is_none()
        {
            return Ok(None);
        }
        Ok(Some(key))
    }
}
