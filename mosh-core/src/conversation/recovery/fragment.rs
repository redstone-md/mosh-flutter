//! Durable sequential assembly using the existing bounded fragment envelope.
use crate::conversation::{decode, encode};
pub(crate) use crate::message_deletion::fragment_buffer::PageFragment;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
pub(crate) const CHUNK: usize = 3000;
pub(crate) const MAX_RECORD: usize = 256 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PartialRecord {
    digest: String,
    total: usize,
    bytes: Vec<u8>,
}

pub(crate) fn fragment(bytes: &[u8], offset: usize) -> Result<PageFragment, String> {
    if bytes.is_empty()
        || bytes.len() > MAX_RECORD
        || offset >= bytes.len()
        || !offset.is_multiple_of(CHUNK)
    {
        return Err("history fragment exceeds bounded record".into());
    }
    Ok(PageFragment {
        digest: hex::encode(Sha256::digest(bytes)),
        total: bytes.len(),
        offset,
        bytes_b64: encode(&bytes[offset..bytes.len().min(offset + CHUNK)]),
    })
}

impl PartialRecord {
    pub(crate) fn digest(&self) -> &str {
        &self.digest
    }

    pub(crate) fn offset(&self) -> usize {
        self.bytes.len()
    }

    pub(crate) fn accept(
        current: &mut Option<Self>,
        fragment: PageFragment,
    ) -> Result<Option<Vec<u8>>, String> {
        if fragment.total == 0
            || fragment.total > MAX_RECORD
            || fragment.offset >= fragment.total
            || !fragment.offset.is_multiple_of(CHUNK)
            || fragment.digest.len() != 64
            || fragment.bytes_b64.len() > 4 * CHUNK / 3 + 8
        {
            return Err("invalid bounded history fragment".into());
        }
        let bytes = decode(&fragment.bytes_b64).map_err(|e| e.to_string())?;
        if bytes.len() != CHUNK.min(fragment.total - fragment.offset) {
            return Err("invalid history fragment length".into());
        }
        let partial = current.get_or_insert_with(|| Self {
            digest: fragment.digest.clone(),
            total: fragment.total,
            bytes: Vec::new(),
        });
        if partial.digest != fragment.digest
            || partial.total != fragment.total
            || partial.bytes.len() != fragment.offset
        {
            return Err("history fragment window differs".into());
        }
        partial.bytes.extend(bytes);
        if partial.bytes.len() != partial.total {
            return Ok(None);
        }
        if hex::encode(Sha256::digest(&partial.bytes)) != partial.digest {
            return Err("history record digest differs".into());
        }
        Ok(current.take().map(|partial| partial.bytes))
    }
}
