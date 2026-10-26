use super::super::invalid;
use super::super::types::Result;
use crate::device_link::types::DeviceDescriptor;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct HistoryImport {
    #[serde(flatten)]
    pub progress: crate::conversation::recovery::cursor::HistoryCursor,
    pub source_device_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partial: Option<PartialText>,
}

impl HistoryImport {
    pub fn new(request_id: &str, source: &DeviceDescriptor) -> Self {
        Self {
            progress: crate::conversation::recovery::cursor::HistoryCursor {
                request_id: format!("history-{request_id}"),
                ..Default::default()
            },
            source_device_id: source.device_id.clone(),
            partial: None,
        }
    }

    pub fn accept(&mut self, batch: &HistoryBatch) -> Result<Vec<super::records::TextRecord>> {
        self.progress
            .check(
                &batch.request_id,
                batch.offset,
                &batch.manifest,
                batch.total,
                batch.records.len(),
            )
            .map_err(|_| invalid())?;
        let records = self.assemble(batch)?;
        self.progress
            .advance(
                &batch.manifest,
                batch.total,
                records.len(),
                self.partial.is_some(),
            )
            .map_err(|_| invalid())?;
        Ok(records)
    }
}

impl std::ops::Deref for HistoryImport {
    type Target = crate::conversation::recovery::cursor::HistoryCursor;
    fn deref(&self) -> &Self::Target {
        &self.progress
    }
}
impl std::ops::DerefMut for HistoryImport {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.progress
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
