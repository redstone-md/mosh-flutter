use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use super::MessageOrigin;

#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeleteScope {
    ForMe,
    ForEveryone,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeletionStatus {
    Pending,
    Confirmed,
    Rejected,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeleteMessagesResult {
    pub deleted_count: usize,
    pub local_only_count: usize,
    pub pending_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeletionSummary {
    pub pending_count: usize,
    pub rejected_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeletionMarker {
    pub scope: DeleteScope,
    pub status: DeletionStatus,
    pub administrator: Option<String>,
}

/// Origin and tombstone survive content erasure. Action flags are recomputed
/// by the native owner before snapshots; incoming flags never grant authority.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<MessageOrigin>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deletion: Option<DeletionMarker>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deletion_key: Option<String>,
    #[serde(default)]
    pub can_delete_for_everyone: bool,
    #[serde(default)]
    pub local_only: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_own: Option<bool>,
}
