use crate::conversation::{decode, encode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

pub(super) const CHUNK: usize = 3000;
const MAX_PAGE: usize = 200_000;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PageFragment {
    pub digest: String,
    pub offset: usize,
    pub total: usize,
    pub bytes_b64: String,
}

struct PartialPage {
    total: usize,
    chunks: BTreeMap<usize, Vec<u8>>,
}

#[derive(Default)]
pub(crate) struct FragmentBuffer {
    pages: BTreeMap<String, PartialPage>,
}

pub(crate) fn split_bytes(bytes: &[u8]) -> Result<Vec<PageFragment>, String> {
    if bytes.len() > MAX_PAGE {
        return Err("deletion page exceeds limit".into());
    }
    let digest = hex::encode(Sha256::digest(bytes));
    let total = bytes.len();
    Ok(bytes
        .chunks(CHUNK)
        .enumerate()
        .map(|(index, bytes)| PageFragment {
            digest: digest.clone(),
            offset: index * CHUNK,
            total,
            bytes_b64: encode(bytes),
        })
        .collect())
}

impl FragmentBuffer {
    pub(crate) fn add(
        &mut self,
        carrier: &str,
        fragment: PageFragment,
    ) -> Result<Option<Vec<u8>>, String> {
        let bytes = decode(&fragment.bytes_b64).map_err(|e| e.to_string())?;
        self.validate(&fragment, &bytes)?;
        let key = format!("{carrier}:{}", fragment.digest);
        if !self.pages.contains_key(&key) && self.pages.len() >= 16 {
            self.pages.pop_first();
        }
        let page = self
            .pages
            .entry(key.clone())
            .or_insert_with(|| PartialPage {
                total: fragment.total,
                chunks: Default::default(),
            });
        if page.total != fragment.total
            || page
                .chunks
                .get(&fragment.offset)
                .is_some_and(|old| old != &bytes)
        {
            return Err("conflicting deletion fragment".into());
        }
        page.chunks.insert(fragment.offset, bytes);
        if page.chunks.values().map(Vec::len).sum::<usize>() != fragment.total {
            return Ok(None);
        }
        let bytes: Vec<_> = self
            .pages
            .remove(&key)
            .ok_or("missing deletion page")?
            .chunks
            .into_values()
            .flatten()
            .collect();
        if hex::encode(Sha256::digest(&bytes)) != fragment.digest {
            return Err("deletion page digest mismatch".into());
        }
        Ok(Some(bytes))
    }

    fn validate(&self, fragment: &PageFragment, bytes: &[u8]) -> Result<(), String> {
        if fragment.total == 0
            || fragment.total > MAX_PAGE
            || fragment.offset >= fragment.total
            || !fragment.offset.is_multiple_of(CHUNK)
            || bytes.len() != CHUNK.min(fragment.total - fragment.offset)
            || fragment.digest.len() != 64
        {
            return Err("invalid deletion fragment".into());
        }
        Ok(())
    }
}
