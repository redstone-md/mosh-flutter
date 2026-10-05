use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashSet},
    sync::Arc,
};

use super::{DeleteScope, DeletionError, DeletionMarker, DeletionStatus};
use crate::conversation::message_log::{ConversationMessage, MessageLog};
use crate::persistence::{HistoryTables, Persistence};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DeletionRecord {
    pub context: String,
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub personal_correlation: Option<String>,
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
    pub(crate) fn visible_to_account(&self, user: &str) -> bool {
        (self.scope == DeleteScope::ForMe && self.owner == user && !self.local_only)
            || (self.scope == DeleteScope::ForEveryone && self.status != DeletionStatus::Rejected)
    }

    pub(crate) fn merged(&self, incoming: &Self) -> Self {
        if self.scope == DeleteScope::ForMe
            && self.personal_correlation.is_none()
            && incoming.personal_correlation.is_some()
        {
            return incoming.clone();
        }
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

    pub(crate) fn matches(&self, target: &str, personal_correlation: Option<&str>) -> bool {
        self.key == target
            || (self.scope == DeleteScope::ForMe
                && (self.personal_correlation.as_deref() == Some(target)
                    || personal_correlation.is_some_and(|key| {
                        self.key == key || self.personal_correlation.as_deref() == Some(key)
                    })))
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
    pub accepted: std::collections::BTreeSet<String>,
    pub last_sync: u64,
    pub(super) fragments: super::fragment_buffer::FragmentBuffer,
}

impl DeletionBook {
    pub fn has_shared_records(&self) -> bool {
        self.records.values().any(|record| {
            record.scope == DeleteScope::ForEveryone && record.status != DeletionStatus::Rejected
        })
    }

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
            accepted: Default::default(),
            last_sync: 0,
            fragments: Default::default(),
        }
    }

    pub fn user(&self) -> Result<String, DeletionError> {
        let Some(store) = &self.store else {
            return Ok("local".into());
        };
        let Some(bytes) = store
            .get_device_link()
            .map_err(|e| DeletionError::Persistence(e.to_string()))?
        else {
            return Ok("local".into());
        };
        let identity: crate::device_link::identity::LocalIdentity = serde_json::from_slice(&bytes)
            .map_err(|e| DeletionError::Persistence(e.to_string()))?;
        if !identity
            .roster
            .devices()
            .map_err(|e| DeletionError::Persistence(e.to_string()))?
            .contains(&identity.device)
        {
            return Err(DeletionError::Revoked);
        }
        Ok(identity.roster.user_id())
    }

    pub fn reload(&mut self) -> Result<(), String> {
        if let Some(store) = &self.store {
            self.accepted = store
                .accepted_deletions(&self.context)
                .map_err(|e| e.to_string())?;
            for record in store
                .deletion_records(&self.context)
                .map_err(|e| e.to_string())?
            {
                self.records.insert(record.storage_key(), record);
            }
        }
        Ok(())
    }
}

pub(super) fn validate_selection<M: ConversationMessage>(
    log: &MessageLog<M>,
    ids: &[String],
) -> Result<HashSet<String>, DeletionError> {
    if ids.is_empty() || ids.len() > 1000 {
        return Err(DeletionError::InvalidInput(
            "select between 1 and 1000 messages".into(),
        ));
    }
    let ids: HashSet<_> = ids.iter().cloned().collect();
    for id in &ids {
        if log.iter().filter(|m| m.message_id() == Some(id)).count() != 1 {
            return Err(DeletionError::InvalidInput(
                "selected message is missing or ambiguous".into(),
            ));
        }
    }
    Ok(ids)
}
