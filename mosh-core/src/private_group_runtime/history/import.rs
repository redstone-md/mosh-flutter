//! Current holder claims never bypass original proof or our own recipient entitlement.
use super::*;
use super::{protocol::CheckedFrame, records::GroupRecord};
use crate::conversation::recovery::{
    coordinator::{Checkpoint, Coordinator},
    fragment::{PageFragment, PartialRecord},
    manifest::HistoryKey,
    GroupAcceptanceBasis,
};
use crate::persistence::history_admission::EvidenceWrite;
use sha2::{Digest, Sha256};

impl GroupSession {
    pub(super) fn import_history(
        &mut self,
        checked: &CheckedFrame,
        manifest: String,
        total: usize,
        offset: usize,
        mut records: Vec<GroupRecord>,
        fragment: Option<PageFragment>,
    ) -> Result<(), PrivateGroupError> {
        if !self.recovery.has_source(&checked.frame) || !self.recovery.checkpoint.journal_complete {
            return Ok(());
        }
        let mut next = self.recovery.checkpoint.clone();
        if checked.body.erased_fragment {
            if !records.is_empty()
                || fragment
                    .as_ref()
                    .is_none_or(|fragment| fragment.offset != 0)
            {
                return Err(PrivateGroupError::Codec(
                    "invalid erased fragment replacement".into(),
                ));
            }
            next.partial = None;
        }
        next.progress
            .check(
                &checked.frame.request_id,
                offset,
                &manifest,
                total,
                records.len(),
            )
            .map_err(PrivateGroupError::Codec)?;
        assemble_records(&mut next, &mut records, fragment)?;
        let mut rows = Vec::new();
        let mut evidence = Vec::new();
        let mut keys = Vec::new();
        let mut ids = std::collections::HashSet::new();
        for record in records {
            if !ids.insert(record.message_id.clone()) {
                return Err(PrivateGroupError::Codec(
                    "duplicate group history occurrence".into(),
                ));
            }
            record.verify(self, &checked.sender)?;
            keys.push(HistoryKey {
                message_id: record.message_id.clone(),
                sent_at_ms: record.sent_at_ms,
                digest: record.acceptance.record_hash.clone(),
            });
            let (row, retained) = self.imported_history_row(record, &checked.sender)?;
            rows.push(row);
            evidence.extend(retained);
        }
        next.progress
            .advance(&manifest, total, rows.len(), next.partial.is_some())
            .map_err(PrivateGroupError::Codec)?;
        let receipts =
            self.history_manifest_receipts(&checked.frame.request_id, &next, offset, &keys)?;
        Coordinator::finished(&mut next, &checked.frame.sender_key);
        self.save_history(next, &rows, &evidence, &receipts)?;
        self.recovery.last_progress = now_ms();
        self.pull_history(now_ms())
    }

    fn imported_history_row(
        &mut self,
        record: GroupRecord,
        holder: &crate::sender_auth::VerifiedSender,
    ) -> Result<(StoredMessage<GroupMessage>, Vec<EvidenceWrite>), PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .clone();
        if let Some(indexed) =
            store.history_occurrence(GROUP_HISTORY, &self.group_id, &record.message_id)?
        {
            if Some(&indexed.identity)
                != record
                    .acceptance
                    .origin
                    .as_ref()
                    .map(|o| o.key())
                    .transpose()
                    .map_err(PrivateGroupError::Codec)?
                    .as_ref()
                || indexed
                    .content_digest
                    .as_ref()
                    .is_some_and(|hash| hash != &record.acceptance.record_hash)
            {
                return Err(PrivateGroupError::Codec(
                    "conflicting group history occurrence".into(),
                ));
            }
            if let Some(row) = store.history_row::<GroupMessage>(GROUP_HISTORY, &indexed.row_key)? {
                return self
                    .retained_or_repaired_row(row, &record)
                    .map(|row| (row, Vec::new()));
            }
        }
        let deletion = self.history_record_erasure(&record, &hex::encode(&holder.mls_signer))?;
        let mut message = record.message();
        if let Some(deletion) = deletion {
            let metadata = message
                .metadata
                .as_mut()
                .ok_or(PrivateGroupError::NotReady)?;
            metadata.deletion_key = Some(deletion.key);
            metadata.deletion = Some(crate::message_deletion::DeletionMarker {
                scope: deletion.scope,
                status: deletion.status,
                administrator: deletion.administrator,
            });
        }
        if let Some(metadata) = &mut message.metadata {
            metadata.is_own =
                Some(record.acceptance.original_author_moss_key == self.device_fingerprint);
        }
        let mut accepted = record.acceptance.clone();
        accepted.offer = record.offer.clone();
        accepted.basis = GroupAcceptanceBasis::InheritedImport;
        let previous = accepted
            .receipt
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let mut evidence = vec![EvidenceWrite {
            key: format!(
                "group/{}/evidence/acceptance/{}",
                hex::encode(Sha256::digest(self.group_id.as_bytes())),
                previous.hash()?
            ),
            bytes: serde_json::to_vec(previous)
                .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        }];
        let reference = record.author_checkpoint.reference()?;
        evidence.push(EvidenceWrite {
            key: format!(
                "group/{}/evidence/membership/{}",
                hex::encode(Sha256::digest(self.group_id.as_bytes())),
                reference.tuple().1
            ),
            bytes: serde_json::to_vec(&record.author_checkpoint)
                .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        });
        accepted.receipt = super::receipts::AcceptanceEvidenceV1::native(self, &accepted)?;
        evidence.extend(accepted.first_write(
            &store,
            native_acceptance_key(&self.group_id, &record.message_id),
            false,
            &self.group_id,
        )?);
        let mut row = self.received_text_row(&message, &accepted)?;
        if let Some(evidence) = &mut row.history_evidence {
            evidence.holder_key = holder.peer_id.clone();
        }
        Ok((row, evidence))
    }

    fn retained_or_repaired_row(
        &self,
        mut row: StoredMessage<GroupMessage>,
        record: &GroupRecord,
    ) -> Result<StoredMessage<GroupMessage>, PrivateGroupError> {
        if row.conversation_id != self.group_id
            || row.message_id != record.message_id
            || row.sent_at_ms != record.sent_at_ms
            || row.message.body != record.body
        {
            return Err(PrivateGroupError::Codec(
                "retained group identity differs".into(),
            ));
        }
        if row
            .message
            .metadata
            .as_ref()
            .is_some_and(|m| m.deletion.is_some())
        {
            return Ok(row);
        }
        if self.row_matches_original(&row, record) {
            return Ok(row);
        }
        if row.preview_manifest.is_none() && row.attachment_manifest.is_some() {
            row.preview_manifest = record
                .offer
                .as_ref()
                .and_then(|o| o.preview_manifest.clone());
            if row.preview_manifest.is_some() && self.row_matches_original(&row, record) {
                // Keep ownership, read/deletion state and the first local
                // receipt; only the lost original preview is reconstructed.
                return Ok(row);
            }
        }
        Err(PrivateGroupError::Codec(
            "retained group content differs".into(),
        ))
    }

    fn row_matches_original(
        &self,
        row: &StoredMessage<GroupMessage>,
        record: &GroupRecord,
    ) -> bool {
        serde_json::to_value(&row.message.attachment).ok()
            == serde_json::to_value(&record.message().attachment).ok()
            && GroupRecord::key(row, &self.deletions.context, &self.mesh_id)
                .ok()
                .flatten()
                .is_some_and(|key| key.digest == record.acceptance.record_hash)
    }

    fn history_manifest_receipts(
        &self,
        request: &str,
        next: &Checkpoint,
        offset: usize,
        keys: &[HistoryKey],
    ) -> Result<Vec<EvidenceWrite>, PrivateGroupError> {
        let prefix = format!(
            "{}\u{1}request\u{1}{}\u{1}receipts\u{1}",
            self.checkpoint_key(),
            request
        );
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        if next.progress.complete
            && store.recovery_digest_with_tail(&prefix, Some(&self.deletions.context), keys)?
                != next.progress.manifest.as_deref().unwrap_or_default()
        {
            return Err(PrivateGroupError::Codec(
                "group history frozen manifest differs".into(),
            ));
        }
        keys.iter()
            .enumerate()
            .map(|(index, key)| {
                Ok(EvidenceWrite {
                    key: format!("{prefix}{:020}", offset + index),
                    bytes: serde_json::to_vec(key)
                        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
                })
            })
            .collect()
    }
}

fn assemble_records(
    next: &mut Checkpoint,
    records: &mut Vec<GroupRecord>,
    fragment: Option<PageFragment>,
) -> Result<(), PrivateGroupError> {
    if let Some(fragment) = fragment {
        if !records.is_empty() {
            return Err(PrivateGroupError::Codec(
                "mixed group history fragment".into(),
            ));
        }
        if let Some(bytes) =
            PartialRecord::accept(&mut next.partial, fragment).map_err(PrivateGroupError::Codec)?
        {
            records.push(
                serde_json::from_slice(&bytes)
                    .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
            );
        }
    } else if next.partial.is_some() && records.len() == 1 && records[0].erased.is_some() {
        next.partial = None;
    } else if next.partial.is_some() {
        return Err(PrivateGroupError::Codec(
            "group history partial record missing".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
#[path = "import_tests.rs"]
pub(super) mod tests;

#[cfg(test)]
#[path = "repair_tests.rs"]
mod repair_tests;
