//! Restore org sessions and persist their local membership records.

use super::*;

impl OrgRuntime {
    /// Restart sessions for every persisted org record. Individual failures
    /// (e.g. a port in use) skip that org rather than aborting startup.
    pub fn rehydrate(&mut self) {
        let Some(p) = self.persistence.as_ref().cloned() else {
            return;
        };
        let rows = match p.list_org_records() {
            Ok(rows) => rows,
            Err(_) => return,
        };
        for (_key, bytes) in rows {
            let record: PersistedOrgRecord = match serde_json::from_slice(&bytes) {
                Ok(record) => record,
                Err(_) => continue,
            };
            if self.orgs.contains_key(&record.org_pubkey) {
                continue;
            }
            let Ok(node) =
                self.open_org_room(&record.mesh_id, record.listen_port, &record.static_peer)
            else {
                continue;
            };
            let Ok(signer) = self.signing_key() else {
                continue;
            };
            let session = self.build_session(record, node, signer);
            self.orgs.insert(session.org_pubkey.clone(), session);
        }
    }

    pub(super) fn build_session(
        &self,
        record: PersistedOrgRecord,
        node: Arc<MossNode>,
        signer: SigningKey,
    ) -> OrgSession {
        let own_peer_id = org_signing::peer_id_hex(&signer);
        let (roster, roster_bytes) = self
            .load_roster(&record.org_pubkey)
            .map(|(r, b)| (Some(r), Some(b)))
            .unwrap_or((None, None));
        let mut session = OrgSession {
            control_channel: format!("{ORG_CONTROL_PREFIX}{}", record.mesh_id),
            org_pubkey: record.org_pubkey,
            org_name: record.org_name,
            mesh_id: record.mesh_id,
            display_name: record.display_name,
            listen_port: record.listen_port,
            static_peer: record.static_peer,
            node,
            signer,
            own_peer_id,
            roster,
            roster_bytes,
            dm_offers: Vec::new(),
            group_offers: Vec::new(),
            dm_links: record.dm_links,
            seen_offer_ids: std::collections::HashSet::new(),
            resolved_offer_ids: record.resolved_offer_ids,
            pending_acceptances: record.pending_acceptances,
            #[cfg(test)]
            roster_publishes: 0,
        };
        session.restore_pending_offers();
        session
    }

    /// Re-verify the self-stored roster bytes. `stored_version: None` because
    /// the stored copy IS the reference version.
    pub(super) fn load_roster(&self, org_pubkey: &str) -> Option<(Roster, Vec<u8>)> {
        let p = self.persistence.as_ref()?;
        let bytes = p.get_org_roster(org_pubkey).ok()??;
        let roster = org_roster::verify(&bytes, org_pubkey, None).ok()?;
        Some((roster, bytes))
    }

    pub(super) fn signing_key(&self) -> Result<SigningKey, OrgError> {
        let p = self
            .persistence
            .as_ref()
            .ok_or(OrgError::IdentityUnavailable)?;
        let blob = p
            .get_moss_identity()
            .map_err(|e| OrgError::Persistence(e.to_string()))?
            .ok_or(OrgError::IdentityUnavailable)?;
        org_signing::signing_key_from_identity(&blob).map_err(|_| OrgError::IdentityUnavailable)
    }

    pub(super) fn persist_record(
        &mut self,
        record: PersistedOrgRecord,
    ) -> Result<PersistedOrgRecord, OrgError> {
        let record = persist_org_record(self.persistence.as_deref(), record)?;
        if let Some(session) = self.orgs.get_mut(&record.org_pubkey) {
            session
                .resolved_offer_ids
                .extend(record.resolved_offer_ids.iter().cloned());
            session.prune_resolved_acceptances();
        }
        Ok(record)
    }

    /// A late Welcome retires disk state without another runtime lock.
    pub(super) fn refresh_acceptances(&mut self) {
        let Some(store) = self.persistence.as_deref() else {
            return;
        };
        for session in self
            .orgs
            .values_mut()
            .filter(|session| !session.pending_acceptances.is_empty())
        {
            match read_org_record(store, &session.org_pubkey) {
                Ok(Some(record)) => {
                    session.resolved_offer_ids.extend(record.resolved_offer_ids);
                    session.prune_resolved_acceptances();
                }
                Ok(None) => {}
                Err(error) => dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    &session.org_pubkey,
                    &format!("resolved offers refresh failed: {error}"),
                ),
            }
        }
    }
}

pub(super) fn persist_org_record(
    store: Option<&Persistence>,
    record: PersistedOrgRecord,
) -> Result<PersistedOrgRecord, OrgError> {
    let Some(store) = store else {
        return Ok(record);
    };
    store
        .put_reconciled_org_record(record)
        .map_err(|e| OrgError::Persistence(e.to_string()))
}

fn read_org_record(store: &Persistence, key: &str) -> Result<Option<PersistedOrgRecord>, OrgError> {
    store
        .get_org_record(key)
        .map_err(|error| OrgError::Persistence(error.to_string()))?
        .map(|bytes| {
            serde_json::from_slice(&bytes).map_err(|error| OrgError::Codec(error.to_string()))
        })
        .transpose()
}
