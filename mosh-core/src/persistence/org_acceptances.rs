//! Retire accepted offers with their native MLS state, without another runtime lock.
use super::*;
use crate::org_runtime::{PendingAcceptance, PersistedOrgRecord};
use redb::TableHandle;
use serde::Deserialize;

#[derive(Deserialize)]
struct DmState {
    session_id: String,
    signer_public: Vec<u8>,
    group_id: Vec<u8>,
}

#[derive(Deserialize)]
struct GroupState {
    group_id: String,
    signer_public: Vec<u8>,
    mls_group_id: Vec<u8>,
    joined: bool,
}

impl Persistence {
    pub(super) fn write_org_record(
        &self,
        tx: &redb::WriteTransaction,
        org: &str,
        mut candidate: PersistedOrgRecord,
    ) -> Result<PersistedOrgRecord, PersistenceError> {
        if let Some(bytes) = self.read_transaction_blob(tx, ORG_RECORDS, org)? {
            let stored: PersistedOrgRecord = decode_record(&bytes)?;
            candidate
                .resolved_offer_ids
                .extend(stored.resolved_offer_ids);
            for (id, pending) in stored.pending_acceptances {
                candidate.pending_acceptances.entry(id).or_insert(pending);
            }
        }
        candidate
            .pending_acceptances
            .retain(|id, _| !candidate.resolved_offer_ids.contains(id));
        self.retire_completed_acceptances(tx, &mut candidate, None)?;
        self.save_org_record(tx, org, &candidate)?;
        Ok(candidate)
    }

    pub(super) fn retire_accepted_offers(
        &self,
        tx: &redb::WriteTransaction,
        native_table: Rows,
        native_id: &str,
    ) -> Result<(), PersistenceError> {
        let records = {
            let rows = tx.open_table(ORG_RECORDS).map_err(db_error)?;
            rows.iter()
                .map_err(db_error)?
                .map(|row| {
                    let (key, value) = row.map_err(db_error)?;
                    Ok((key.value().to_string(), value.value().to_vec()))
                })
                .collect::<Result<Vec<_>, PersistenceError>>()?
        };
        for (org, blob) in records {
            let Some(mut record) = self.read_retirement_record(&org, &blob) else {
                continue;
            };
            if self.retire_completed_acceptances(
                tx,
                &mut record,
                Some((native_table, native_id)),
            )? {
                self.save_org_record(tx, &org, &record)?;
            }
        }
        Ok(())
    }

    fn retire_completed_acceptances(
        &self,
        tx: &redb::WriteTransaction,
        record: &mut PersistedOrgRecord,
        native: Option<(Rows, &str)>,
    ) -> Result<bool, PersistenceError> {
        let mut completed = Vec::new();
        for (id, pending) in &record.pending_acceptances {
            if native.is_some_and(|(table, id)| !matches_native(pending, table, id)) {
                continue;
            }
            if self.native_acceptance_is_durable(tx, pending)? {
                completed.push(id.clone());
            }
        }
        let changed = !completed.is_empty();
        for id in completed {
            record.pending_acceptances.remove(&id);
            record.resolved_offer_ids.insert(id);
        }
        Ok(changed)
    }

    fn native_acceptance_is_durable(
        &self,
        tx: &redb::WriteTransaction,
        pending: &PendingAcceptance,
    ) -> Result<bool, PersistenceError> {
        let id = pending.conversation_id();
        let (records, snapshots) = match pending {
            PendingAcceptance::Dm { .. } => (SESSIONS, MLS_SNAPSHOT),
            PendingAcceptance::Group { .. } => (GROUPS, GROUP_MLS_SNAPSHOT),
        };
        let Some(bytes) = self.read_transaction_blob(tx, records, id)? else {
            return Ok(false);
        };
        let ready = match pending {
            PendingAcceptance::Dm { .. } => {
                let state: DmState = decode_record(&bytes)?;
                state.session_id == id
                    && state.signer_public == pending.signer_public()
                    && !state.group_id.is_empty()
            }
            PendingAcceptance::Group { .. } => {
                let state: GroupState = decode_record(&bytes)?;
                state.group_id == id
                    && state.signer_public == pending.signer_public()
                    && state.joined
                    && !state.mls_group_id.is_empty()
            }
        };
        if !ready {
            return Ok(false);
        }
        Ok(self
            .read_transaction_blob(tx, snapshots, id)?
            .is_some_and(|snapshot| !snapshot.is_empty()))
    }

    fn read_transaction_blob(
        &self,
        tx: &redb::WriteTransaction,
        table: Rows,
        key: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        let rows = tx.open_table(table).map_err(db_error)?;
        let row = rows.get(key).map_err(db_error)?;
        row.map(|row| decrypt_blob(&self.dek, row.value()))
            .transpose()
    }

    fn read_retirement_record(&self, org: &str, blob: &[u8]) -> Option<PersistedOrgRecord> {
        decrypt_blob(&self.dek, blob)
            .and_then(|bytes| decode_record(&bytes))
            .inspect_err(|error| {
                dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    org,
                    &format!("unreadable org record skipped during native acceptance: {error}"),
                );
            })
            .ok()
    }

    fn save_org_record(
        &self,
        tx: &redb::WriteTransaction,
        org: &str,
        record: &PersistedOrgRecord,
    ) -> Result<(), PersistenceError> {
        let bytes =
            serde_json::to_vec(record).map_err(|e| PersistenceError::Json(e.to_string()))?;
        let blob = encrypt_blob(&self.dek, &bytes)?;
        Self::update_row(tx, ORG_RECORDS, org, Some(&blob))
    }
}

pub(super) fn decode_record<T: serde::de::DeserializeOwned>(
    bytes: &[u8],
) -> Result<T, PersistenceError> {
    serde_json::from_slice(bytes).map_err(|e| PersistenceError::Json(e.to_string()))
}

fn matches_native(pending: &PendingAcceptance, table: Rows, id: &str) -> bool {
    let kind_matches = match pending {
        PendingAcceptance::Dm { .. } => table.name() == SESSIONS.name(),
        PendingAcceptance::Group { .. } => table.name() == GROUPS.name(),
    };
    kind_matches && pending.conversation_id() == id
}
