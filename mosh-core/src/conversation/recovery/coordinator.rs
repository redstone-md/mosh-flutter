//! Shared bounded source rounds; adapters own proof policy, transport and durable installation.
use super::{cursor::HistoryCursor, manifest::Manifest, wire::HistoryFrame, HistorySyncReason};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Checkpoint {
    pub(crate) round: u64,
    pub(crate) progress: HistoryCursor,
    pub(crate) source: Option<String>,
    pub(crate) observed: BTreeMap<String, String>,
    #[serde(default)]
    pub(crate) partial: Option<crate::conversation::recovery::fragment::PartialRecord>,
    #[serde(default)]
    pub(crate) deletion_digest: String,
    #[serde(default)]
    pub(crate) journal_after: Option<String>,
    #[serde(default)]
    pub(crate) journal_complete: bool,
}

#[derive(Default)]
pub(crate) struct Coordinator {
    pub(crate) checkpoint: Checkpoint,
    pub(crate) pending: Vec<HistoryFrame>,
    pub(crate) cache: Option<(u64, Manifest)>,
    pub(crate) last_probe: u64,
    pub(crate) last_pull: u64,
    pub(crate) last_progress: u64,
    pub(crate) error: Option<HistorySyncReason>,
    pub(crate) restored: bool,
    pub(crate) permit: Option<crate::conversation::recovery::slots::ImportPermit>,
    pub(crate) pending_bytes: usize,
    next_probe: u64,
    backoff: u64,
    peer_revision: u64,
    local_revision: u64,
}

impl Coordinator {
    pub(crate) fn has_source(&self, frame: &HistoryFrame) -> bool {
        self.checkpoint.round == frame.round
            && self.checkpoint.source.as_ref() == Some(&frame.sender_key)
            && self.checkpoint.progress.request_id == frame.request_id
    }

    pub(crate) fn begin_round(&self) -> Result<Checkpoint, String> {
        let mut next = self.checkpoint.clone();
        next.round = next.round.checked_add(1).ok_or("history round overflow")?;
        next.progress = HistoryCursor {
            complete: next.progress.complete,
            request_id: hex::encode(rand::random::<[u8; 16]>()),
            ..Default::default()
        };
        next.source = None;
        next.partial = None;
        next.journal_after = None;
        next.journal_complete = false;
        Ok(next)
    }

    pub(crate) fn installed(&mut self, checkpoint: Checkpoint) {
        if checkpoint.source.is_none() {
            self.permit = None;
        }
        self.checkpoint = checkpoint;
        self.error = None;
    }

    pub(crate) fn queue(&mut self, frame: HistoryFrame) -> Result<(), String> {
        let bytes = serde_json::to_vec(&frame).map_err(|e| e.to_string())?.len();
        if self.pending.len() < 32 && self.pending_bytes + bytes <= 1024 * 1024 {
            self.pending.push(frame);
            self.pending_bytes += bytes;
        }
        Ok(())
    }

    pub(crate) fn drain(&mut self) -> Vec<HistoryFrame> {
        self.pending_bytes = 0;
        std::mem::take(&mut self.pending)
    }
}

impl Coordinator {
    pub(crate) fn observe(&mut self, peers: u64, local: u64) {
        if self.peer_revision != peers || self.local_revision != local {
            self.peer_revision = peers;
            self.local_revision = local;
            self.next_probe = 0;
            self.backoff = 5000;
        }
    }

    pub(crate) fn probe_due(&self, now: u64) -> bool {
        now >= self.next_probe && now.saturating_sub(self.last_probe) >= 2000
    }

    pub(crate) fn probed(&mut self, now: u64) {
        let delay = self.backoff.max(5000);
        self.next_probe = now.saturating_add(delay + rand::random::<u64>() % (delay / 5 + 1));
        self.backoff = delay.saturating_mul(2).min(60_000);
        self.last_probe = now;
    }
}
impl Coordinator {
    pub(crate) fn offered(
        &self,
        frame: &HistoryFrame,
        manifest: String,
        total: usize,
        deletion_digest: String,
        owner: &str,
        context: &str,
    ) -> Result<Option<(Checkpoint, super::slots::ImportPermit)>, String> {
        let current = &self.checkpoint;
        let view = format!("{manifest}:{deletion_digest}");
        if frame.round != current.round
            || frame.request_id != current.progress.request_id
            || current.source.is_some()
            || current.observed.get(&frame.sender_key) == Some(&view)
            || manifest.len() != 64
            || hex::decode(&manifest).is_err()
            || deletion_digest.len() != 64
            || hex::decode(&deletion_digest).is_err()
        {
            return Ok(None);
        }
        let Some(permit) = super::slots::ImportPermit::acquire(owner, context) else {
            return Ok(None);
        };
        let mut next = self.begin_round()?;
        next.source = Some(frame.sender_key.clone());
        next.progress.manifest = Some(manifest);
        next.progress.total = Some(total);
        next.progress.complete = false;
        next.deletion_digest = deletion_digest;
        Ok(Some((next, permit)))
    }

    pub(crate) fn finished(next: &mut Checkpoint, source: &str) {
        if next.progress.complete {
            if next.observed.len() >= 16 {
                next.observed.pop_first();
            }
            next.observed.insert(
                source.into(),
                format!(
                    "{}:{}",
                    next.progress.manifest.as_deref().unwrap_or_default(),
                    next.deletion_digest
                ),
            );
            next.source = None;
        }
    }
}
