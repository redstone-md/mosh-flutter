//! The history window invariant used by DM and room history import.
use serde::{Deserialize, Serialize};

pub(crate) const PAGE_RECORDS: usize = 16;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct HistoryCursor {
    pub request_id: String,
    pub cursor: usize,
    pub manifest: Option<String>,
    pub total: Option<usize>,
    pub complete: bool,
}

impl HistoryCursor {
    pub(crate) fn check(
        &self,
        request: &str,
        offset: usize,
        manifest: &str,
        total: usize,
        records: usize,
    ) -> Result<(), String> {
        if self.complete
            || request != self.request_id
            || offset != self.cursor
            || records > PAGE_RECORDS
            || !super::manifest::canonical_hex(manifest, 64)
            || self.total.is_some_and(|old| old != total)
            || self.manifest.as_deref().is_some_and(|old| old != manifest)
        {
            return Err("history window differs".into());
        }
        Ok(())
    }

    pub(crate) fn advance(
        &mut self,
        manifest: &str,
        total: usize,
        records: usize,
        partial: bool,
    ) -> Result<(), String> {
        let next = self
            .cursor
            .checked_add(records)
            .ok_or("history cursor overflow")?;
        if next > total || (records == 0 && !partial && next < total) {
            return Err("history page makes no progress".into());
        }
        self.cursor = next;
        self.total = Some(total);
        self.manifest = Some(manifest.into());
        self.complete = next == total;
        Ok(())
    }
}
