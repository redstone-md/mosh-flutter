use super::super::history::{HistoryBatch, HistoryExport, HistoryImport, HistoryRequest};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct Recovery {
    pub round: u64,
    pub request_id: String,
    pub started_ms: u64,
    pub last_rx_ms: u64,
    pub required_epoch: u64,
    pub source: Option<RecoverySource>,
    pub observed: HashMap<String, String>,
}

impl Recovery {
    pub fn new(now: u64, epoch: u64) -> Self {
        Self {
            round: 0,
            request_id: String::new(),
            started_ms: 0,
            last_rx_ms: now,
            required_epoch: epoch,
            source: None,
            observed: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoverySource {
    pub device_id: String,
    pub epoch: u64,
    pub import: HistoryImport,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryExport {
    pub round: u64,
    pub export: HistoryExport,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryProbe {
    pub session_id: String,
    pub request_id: String,
    pub round: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryOffer {
    pub probe: RecoveryProbe,
    pub epoch: u64,
    pub manifest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryPull {
    pub round: u64,
    pub epoch: u64,
    pub request: HistoryRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryBatch {
    pub round: u64,
    pub batch: HistoryBatch,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RecoveryEpoch {
    pub round: u64,
    pub request_id: String,
    pub evidence: super::epochs::EpochRecord,
}
