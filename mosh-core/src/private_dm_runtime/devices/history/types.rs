use super::super::invalid;
use super::super::types::Result;
use crate::device_link::types::DeviceDescriptor;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryImport {
    pub request_id: String,
    pub source_device_id: String,
    pub cursor: usize,
    pub manifest: Option<String>,
    pub total: Option<usize>,
    pub complete: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partial: Option<PartialText>,
}

impl HistoryImport {
    pub fn new(request_id: &str, source: &DeviceDescriptor) -> Self {
        Self {
            request_id: format!("history-{request_id}"),
            source_device_id: source.device_id.clone(),
            cursor: 0,
            manifest: None,
            total: None,
            complete: false,
            partial: None,
        }
    }

    pub fn accept(&mut self, batch: &HistoryBatch) -> Result<Vec<super::records::TextRecord>> {
        if self.complete
            || batch.request_id != self.request_id
            || batch.offset != self.cursor
            || batch.records.len() > super::BATCH_RECORDS
            || batch.manifest.len() != 64
            || hex::decode(&batch.manifest).is_err()
            || self.total.is_some_and(|total| total != batch.total)
            || self
                .manifest
                .as_ref()
                .is_some_and(|hash| hash != &batch.manifest)
        {
            return Err(invalid());
        }
        let records = self.assemble(batch)?;
        let next = self.cursor.checked_add(records.len()).ok_or_else(invalid)?;
        if next > batch.total
            || (records.is_empty() && self.partial.is_none() && next < batch.total)
        {
            return Err(invalid());
        }
        self.cursor = next;
        self.total = Some(batch.total);
        self.manifest = Some(batch.manifest.clone());
        self.complete = next == batch.total;
        Ok(records)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct PartialText {
    pub record: super::records::TextRecord,
    pub body_length: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct TextFragment {
    pub record: super::records::TextRecord,
    pub body_offset: usize,
    pub body_length: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryKey {
    pub message_id: String,
    pub sent_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryExport {
    pub request_id: String,
    pub recipient_device_id: String,
    pub keys: Vec<HistoryKey>,
    pub digest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryRequest {
    pub session_id: String,
    pub request_id: String,
    pub offset: usize,
    pub body_offset: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryBatch {
    pub session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub epoch: Option<u64>,
    pub request_id: String,
    pub offset: usize,
    pub total: usize,
    pub manifest: String,
    pub records: Vec<super::records::TextRecord>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fragment: Option<TextFragment>,
}
