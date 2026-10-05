use super::{
    authority::DeletionAuthority, DeleteScope, DeletionContext, DeletionRecord, DeletionStatus,
};
use crate::conversation::message_log::ConversationMessage;

impl<M: ConversationMessage> DeletionContext<'_, M> {
    pub fn reconcile(
        &mut self,
        authority: &DeletionAuthority,
        leaving: bool,
    ) -> Result<(), String> {
        self.reject_local_pending(&authority.local.key, |request| {
            !leaving
                && authority.member_with_proof(&request.actor, request.ownership.as_deref())
                && (!request.moderated || authority.admins.contains(&request.actor))
        })
    }

    pub fn cancel_pending(&mut self, local_key: &str) -> Result<(), String> {
        self.reject_local_pending(local_key, |_| false)
    }

    fn reject_local_pending(
        &mut self,
        local_key: &str,
        permitted: impl Fn(&super::protocol::DeleteRequest) -> bool,
    ) -> Result<(), String> {
        self.book.reload()?;
        if self.book.records.is_empty() {
            return Ok(());
        }
        let owner = self.book.user().map_err(|e| e.to_string())?;
        let mut changes = Vec::new();
        for record in self
            .book
            .records
            .values()
            .filter(|r| r.status == DeletionStatus::Pending)
        {
            let Some(request) = &record.request else {
                continue;
            };
            if request.actor != local_key {
                continue;
            }
            if permitted(request) {
                continue;
            }
            let mut rejected = record.clone();
            rejected.status = DeletionStatus::Rejected;
            changes.push(rejected);
            changes.push(personal_rejection(self, record, request, &owner)?);
        }
        super::application::install(self, &changes, false)
    }
}

fn personal_rejection<M: ConversationMessage>(
    context: &DeletionContext<'_, M>,
    record: &DeletionRecord,
    request: &super::protocol::DeleteRequest,
    owner: &str,
) -> Result<DeletionRecord, String> {
    Ok(DeletionRecord {
        personal_correlation: context
            .log
            .iter()
            .find(|m| m.message_id() == Some(request.target.id.as_str()))
            .map(|m| super::correlation::message_key(&context.book.context, m, context.transfer))
            .transpose()?
            .flatten(),
        context: record.context.clone(),
        key: record.key.clone(),
        scope: DeleteScope::ForMe,
        owner: owner.to_string(),
        local_only: false,
        status: DeletionStatus::Confirmed,
        administrator: None,
        request: None,
        acknowledgement: None,
    })
}
