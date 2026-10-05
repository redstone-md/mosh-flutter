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
        self.book.reload()?;
        let owner = self.book.user()?;
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
            if request.actor != authority.local.key {
                continue;
            }
            if !leaving
                && authority.member(&request.actor)
                && (!request.moderated || authority.admins.contains(&request.actor))
            {
                continue;
            }
            let mut rejected = record.clone();
            rejected.status = DeletionStatus::Rejected;
            changes.push(rejected);
            changes.push(DeletionRecord {
                context: record.context.clone(),
                key: record.key.clone(),
                scope: DeleteScope::ForMe,
                owner: owner.clone(),
                local_only: false,
                status: DeletionStatus::Confirmed,
                administrator: None,
                request: None,
                acknowledgement: None,
            });
        }
        self.book
            .install(self.log, self.attempts, self.transfer, &changes)
    }
}
