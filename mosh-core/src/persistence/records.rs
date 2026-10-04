//! Encrypted identities and organization records.
use super::*;

impl Persistence {
    pub fn put_moss_identity(&self, raw: &[u8]) -> Result<(), PersistenceError> {
        self.put(MOSS_IDENTITY, MOSS_IDENTITY_KEY, raw)
    }

    pub fn get_moss_identity(&self) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(MOSS_IDENTITY, MOSS_IDENTITY_KEY)
    }

    pub fn put_device_link(&self, record: &[u8]) -> Result<(), PersistenceError> {
        self.put(DEVICE_LINK, DEVICE_LINK_KEY, record)
    }

    pub fn get_device_link(&self) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(DEVICE_LINK, DEVICE_LINK_KEY)
    }

    pub fn put_org_roster(
        &self,
        org_pubkey: &str,
        roster_bytes: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(ORG_ROSTERS, org_pubkey, roster_bytes)
    }

    pub fn get_org_roster(&self, org_pubkey: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(ORG_ROSTERS, org_pubkey)
    }

    pub fn put_org_record(&self, org_pubkey: &str, record: &[u8]) -> Result<(), PersistenceError> {
        let record = super::org_acceptances::decode_record(record)?;
        self.write(|tx| self.write_org_record(tx, org_pubkey, record))
            .map(|_| ())
    }

    /// Return the canonical record only after its encrypted transaction commits.
    pub(crate) fn put_reconciled_org_record(
        &self,
        record: crate::org_runtime::PersistedOrgRecord,
    ) -> Result<crate::org_runtime::PersistedOrgRecord, PersistenceError> {
        let org = record.org_pubkey.clone();
        self.write(|tx| self.write_org_record(tx, &org, record))
    }

    pub fn get_org_record(&self, org_pubkey: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(ORG_RECORDS, org_pubkey)
    }

    pub fn list_org_rosters(&self) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        self.list_rows(ORG_ROSTERS)
    }

    pub fn list_org_records(&self) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        self.list_rows(ORG_RECORDS)
    }

    /// Leaving an org removes its record and cached roster atomically.
    pub fn delete_org(&self, org_pubkey: &str) -> Result<(), PersistenceError> {
        self.write(|tx| {
            for table in [ORG_RECORDS, ORG_ROSTERS] {
                Self::update_row(tx, table, org_pubkey, None)?;
            }
            Ok(())
        })
    }
}

impl crate::moss_ffi::MossKeyStore for Persistence {
    fn load_identity(&self) -> Option<Vec<u8>> {
        match self.get_moss_identity() {
            Ok(value) => value,
            Err(e) => {
                dlog::write(
                    LogLevel::Error,
                    kinds::IDENTITY,
                    "",
                    &format!("moss identity load failed: {e}"),
                );
                None
            }
        }
    }

    fn save_identity(&self, bytes: &[u8]) {
        if let Err(e) = self.put_moss_identity(bytes) {
            dlog::write(
                LogLevel::Error,
                kinds::IDENTITY,
                "",
                &format!("moss identity save failed: {e}"),
            );
        }
    }
}
