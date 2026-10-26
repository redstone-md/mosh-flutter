//! Shared wire ordering and fragment progress; kind adapters retain deletion authority.
use super::fragment::PartialRecord;
use crate::message_deletion::{protocol::DeletionMessage, DeletionRecord};

pub(crate) fn assemble(
    partial: &mut Option<PartialRecord>,
    page: DeletionMessage,
) -> Result<Option<DeletionMessage>, String> {
    if let DeletionMessage::Fragment(fragment) = page {
        return PartialRecord::accept(partial, fragment)?
            .map(|bytes| serde_json::from_slice(&bytes).map_err(|e| e.to_string()))
            .transpose();
    }
    if partial.is_some() {
        return Err("history journal partial missing".into());
    }
    Ok(Some(page))
}

pub(crate) fn validate_window(
    records: &[DeletionRecord],
    previous: Option<&str>,
    next: Option<&str>,
) -> Result<(), String> {
    let mut last = previous.map(str::to_owned);
    for record in records {
        let key = record.storage_key();
        if last.as_ref().is_some_and(|old| old >= &key) {
            return Err("history journal keys are not ordered".into());
        }
        last = Some(key);
    }
    if records.len() > 16
        || next.is_some_and(|next| records.is_empty() || last.as_deref() != Some(next))
    {
        return Err("history journal makes no progress".into());
    }
    Ok(())
}
