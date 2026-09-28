use super::{types::*, *};

impl HistoryImport {
    pub(super) fn assemble(
        &mut self,
        batch: &HistoryBatch,
    ) -> Result<Vec<super::records::TextRecord>> {
        let Some(fragment) = &batch.fragment else {
            if self.partial.is_some() {
                return Err(invalid());
            }
            return Ok(batch.records.clone());
        };
        fragment.record.validate()?;
        if !batch.records.is_empty()
            || batch.offset >= batch.total
            || fragment.record.body.is_empty()
        {
            return Err(invalid());
        }
        let mut partial = self.partial.take().unwrap_or_else(|| PartialText {
            record: super::records::TextRecord {
                body: String::new(),
                ..fragment.record.clone()
            },
            body_length: fragment.body_length,
        });
        partial.append(fragment)?;
        if partial.record.body.len() == partial.body_length {
            Ok(vec![partial.record])
        } else {
            self.partial = Some(partial);
            Ok(Vec::new())
        }
    }
}

impl PartialText {
    fn append(&mut self, fragment: &TextFragment) -> Result<()> {
        if self.record.message_id != fragment.record.message_id
            || self.record.sent_at_ms != fragment.record.sent_at_ms
            || self.record.from_device != fragment.record.from_device
            || self.body_length != fragment.body_length
            || self.record.body.len() != fragment.body_offset
            || fragment
                .body_offset
                .checked_add(fragment.record.body.len())
                .is_none_or(|end| end > fragment.body_length)
        {
            return Err(invalid());
        }
        self.record.body.push_str(&fragment.record.body);
        Ok(())
    }
}

impl HistoryBatch {
    pub(super) fn fragment_first(&mut self, offset: usize) -> Result<()> {
        let mut record = self.records.first().cloned().ok_or_else(invalid)?;
        let body_length = record.body.len();
        if offset >= body_length || !record.body.is_char_boundary(offset) {
            return Err(invalid());
        }
        let end = boundary_before(&record.body, offset.saturating_add(64 * 1024));
        record.body = record.body[offset..end].to_string();
        self.records.clear();
        self.fragment = Some(TextFragment {
            record,
            body_length,
            body_offset: offset,
        });
        Ok(())
    }

    pub(super) fn shrink(&mut self) -> Result<()> {
        if self.records.len() > 1 {
            self.records.pop();
        } else if self.fragment.is_none() {
            self.fragment_first(0)?;
        } else {
            let fragment = self.fragment.as_mut().ok_or_else(invalid)?;
            let end = boundary_before(&fragment.record.body, fragment.record.body.len() / 2);
            if end == 0 {
                return Err(invalid());
            }
            fragment.record.body.truncate(end);
        }
        Ok(())
    }
}

fn boundary_before(body: &str, limit: usize) -> usize {
    let mut end = body.len().min(limit);
    while !body.is_char_boundary(end) {
        end -= 1;
    }
    end
}
