use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashSet},
    sync::Arc,
};

use super::{types::DeleteMessagesResult, DeleteScope, DeletionMarker, DeletionStatus};
use crate::conversation::{
    message_log::{ConversationMessage, MessageLog},
    transfer::Transfer,
};
use crate::outbound_delivery::OutboundAttemptRecord;
use crate::persistence::{HistoryTables, Persistence};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DeletionRecord {
    pub context: String,
    pub key: String,
    pub scope: DeleteScope,
    pub owner: String,
    pub local_only: bool,
    pub status: DeletionStatus,
    pub administrator: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub request: Option<super::protocol::DeleteRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acknowledgement: Option<super::protocol::DeleteAck>,
}

impl DeletionRecord {
    pub(crate) fn merged(&self, incoming: &Self) -> Self {
        if self.status == DeletionStatus::Confirmed {
            if incoming.status != DeletionStatus::Confirmed {
                return self.clone();
            }
            let old = self.acknowledgement.as_ref().map(|a| &a.actor);
            let new = incoming.acknowledgement.as_ref().map(|a| &a.actor);
            if old <= new {
                return self.clone();
            }
        }
        if self.status == DeletionStatus::Rejected && incoming.status == DeletionStatus::Pending {
            return self.clone();
        }
        incoming.clone()
    }
    pub fn storage_key(&self) -> String {
        let operation = self.request.as_ref().map_or("", |r| r.operation.as_str());
        format!(
            "{}\u{0001}{}\u{0001}{}\u{0001}{}:{}",
            self.context,
            self.owner,
            if self.scope == DeleteScope::ForMe {
                "personal"
            } else {
                "shared"
            },
            self.key,
            operation
        )
    }

    pub(crate) fn marker(&self) -> DeletionMarker {
        DeletionMarker {
            scope: if self.status == DeletionStatus::Rejected {
                DeleteScope::ForMe
            } else {
                self.scope
            },
            status: self.status,
            administrator: self.administrator.clone(),
        }
    }
}

/// Monotonic tombstones belong to the existing conversation owner. Account
/// synchronization writes the same encrypted journal, without another inbox.
pub(crate) struct DeletionBook {
    pub context: String,
    pub store: Option<Arc<Persistence>>,
    pub tables: HistoryTables,
    pub records: BTreeMap<String, DeletionRecord>,
    pub last_sync: u64,
    pub(super) fragments: super::fragment_buffer::FragmentBuffer,
}

impl DeletionBook {
    pub fn summary(&self) -> Option<super::types::DeletionSummary> {
        let pending_count = self
            .records
            .values()
            .filter(|r| r.status == DeletionStatus::Pending)
            .count();
        let rejected_count = self
            .records
            .values()
            .filter(|r| r.status == DeletionStatus::Rejected)
            .count();
        (pending_count + rejected_count > 0).then_some(super::types::DeletionSummary {
            pending_count,
            rejected_count,
        })
    }
    pub fn new(context: String, tables: HistoryTables, store: Option<Arc<Persistence>>) -> Self {
        Self {
            context,
            tables,
            store,
            records: BTreeMap::new(),
            last_sync: 0,
            fragments: Default::default(),
        }
    }

    pub fn user(&self) -> Result<String, String> {
        let Some(store) = &self.store else {
            return Ok("local".into());
        };
        let Some(bytes) = store.get_device_link().map_err(|e| e.to_string())? else {
            return Ok("local".into());
        };
        let identity: crate::device_link::identity::LocalIdentity =
            serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        if !identity
            .roster
            .devices()
            .map_err(|e| e.to_string())?
            .contains(&identity.device)
        {
            return Err("revoked device cannot delete messages".into());
        }
        Ok(identity.roster.user_id())
    }

    pub fn reload(&mut self) -> Result<(), String> {
        if let Some(store) = &self.store {
            for record in store
                .deletion_records(&self.context)
                .map_err(|e| e.to_string())?
            {
                self.records.insert(record.storage_key(), record);
            }
        }
        Ok(())
    }

    pub fn delete_for_me<M: ConversationMessage>(
        &mut self,
        log: &mut MessageLog<M>,
        attempts: &mut std::collections::HashMap<String, OutboundAttemptRecord>,
        transfer: &mut Transfer,
        ids: &[String],
    ) -> Result<DeleteMessagesResult, String> {
        self.reload()?;
        let ids = validate_selection(log, ids)?;
        let owner = self.user()?;
        let mut records = Vec::new();
        for message in log
            .iter()
            .filter(|m| m.message_id().is_some_and(|id| ids.contains(id)))
        {
            let (key, local_only) = super::target::target(&self.context, message, transfer)?;
            records.push(DeletionRecord {
                context: self.context.clone(),
                key,
                scope: DeleteScope::ForMe,
                owner: owner.clone(),
                local_only,
                status: DeletionStatus::Confirmed,
                administrator: None,
                request: None,
                acknowledgement: None,
            });
        }
        let result = DeleteMessagesResult {
            deleted_count: records.len(),
            local_only_count: records.iter().filter(|r| r.local_only).count(),
            pending_count: 0,
        };
        self.install(log, attempts, transfer, &records)?;
        Ok(result)
    }

    pub fn apply<M: ConversationMessage>(
        &mut self,
        log: &mut MessageLog<M>,
        attempts: &mut std::collections::HashMap<String, OutboundAttemptRecord>,
        transfer: &mut Transfer,
    ) -> Result<(), String> {
        if let Some(store) = &self.store {
            transfer.collect_erased_cache(store);
        }
        self.reload()?;
        if self.records.is_empty() {
            return Ok(());
        }
        let user = self.user()?;
        let records: Vec<_> = self
            .records
            .values()
            .filter(|r| r.owner == user || r.scope == DeleteScope::ForEveryone)
            .cloned()
            .collect();
        self.install(log, attempts, transfer, &records)
    }
}

pub(super) fn validate_selection<M: ConversationMessage>(
    log: &MessageLog<M>,
    ids: &[String],
) -> Result<HashSet<String>, String> {
    if ids.is_empty() || ids.len() > 1000 {
        return Err("select between 1 and 1000 messages".into());
    }
    let ids: HashSet<_> = ids.iter().cloned().collect();
    for id in &ids {
        if log.iter().filter(|m| m.message_id() == Some(id)).count() != 1 {
            return Err("selected message is missing or ambiguous".into());
        }
    }
    Ok(ids)
}
