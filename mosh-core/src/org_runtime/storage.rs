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
        OrgSession {
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
            #[cfg(test)]
            roster_publishes: 0,
        }
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

    pub(super) fn persist_record(&self, record: &PersistedOrgRecord) -> Result<(), OrgError> {
        let Some(p) = self.persistence.as_ref() else {
            return Ok(());
        };
        let bytes = serde_json::to_vec(record).map_err(|e| OrgError::Codec(e.to_string()))?;
        p.put_org_record(&record.org_pubkey, &bytes)
            .map_err(|e| OrgError::Persistence(e.to_string()))
    }
}
