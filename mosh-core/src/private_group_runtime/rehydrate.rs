//! Resume durable groups without letting one corrupt row block startup.

use super::*;

impl PrivateGroupRuntime {
    pub fn rehydrate(&mut self) {
        let Some(store) = self.groups.persistence().cloned() else {
            return;
        };
        for record in self.groups.stored_records::<PersistedGroupSession>() {
            let Some(snapshot) = stored_snapshot(&store, &record) else {
                continue;
            };
            let Some(crypto) = restore_result(
                &record.group_id,
                "crypto restore failed",
                MlsSessionCrypto::restore(
                    &record.display_name,
                    &record.signer_public,
                    &snapshot,
                    &record.mls_group_id,
                ),
            ) else {
                continue;
            };
            let Some(mut session) = self.resume_group(&record, crypto, &store) else {
                continue;
            };
            self.groups.replay(
                &record.group_id,
                Restore {
                    log: &mut session.messages,
                    attempts: &mut session.outbound_attempts,
                    transfer: &mut session.transfer,
                    local_author: &record.device_fingerprint,
                },
            );
            self.groups.mark_record_final(&record.group_id);
            self.groups.insert(record.group_id, session);
        }
    }

    fn resume_group(
        &mut self,
        record: &PersistedGroupSession,
        crypto: MlsSessionCrypto,
        store: &Arc<Persistence>,
    ) -> Option<GroupSession> {
        let node = restore_result(
            &record.group_id,
            "node start failed",
            self.open_group_room(
                &record.mesh_id,
                &record.group_id,
                record.listen_port,
                record.static_peer.clone(),
            ),
        )?;
        let org_signer = restore_result(
            &record.group_id,
            "org signer unavailable",
            record
                .org_pubkey
                .as_ref()
                .map(|_| load_org_signer(Some(store)))
                .transpose(),
        )?;
        let mut restored_record = record.clone();
        restored_record.device_fingerprint = node
            .public_key_hex()
            .unwrap_or_else(|| record.device_fingerprint.clone());
        let mut session = GroupSession::new(
            restored_record,
            node,
            crypto,
            Some(Arc::clone(store)),
            Arc::clone(self.groups.attachment_store()),
            org_signer,
        );
        // The restored MLS tree outranks a stale admin pointer.
        session.reconcile_admin();
        session.request_resume_resync();
        Some(session)
    }
}

impl GroupSession {
    fn request_resume_resync(&self) {
        if !self.joined || self.is_admin {
            return;
        }
        let Some(have_epoch) = self.crypto.epoch() else {
            return;
        };
        // Best-effort while the room reconnects; a later epoch gap retries.
        let _ = self.publish_control(&ControlEnvelope::ResyncRequest {
            group_id: self.group_id.clone(),
            from_fingerprint: self.crypto.fingerprint(),
            have_epoch,
        });
    }
}

fn stored_snapshot(store: &Persistence, record: &PersistedGroupSession) -> Option<Vec<u8>> {
    match store.get_group_mls_snapshot(&record.group_id) {
        Ok(Some(snapshot)) => Some(snapshot),
        Ok(None) => {
            // Unjoined placeholders have no recoverable MLS state. Keep other
            // rows so their history remains available for recovery.
            let (level, message) = if record.mls_group_id.is_empty() && !record.joined {
                let message = match store.delete_group(&record.group_id) {
                    Ok(()) => "dropping joiner record without MLS snapshot".to_string(),
                    Err(error) => {
                        format!("joiner record without MLS snapshot; delete failed: {error}")
                    }
                };
                (LogLevel::Info, message)
            } else {
                (
                    LogLevel::Warn,
                    "record without MLS snapshot; row kept".into(),
                )
            };
            dlog::write(level, kinds::REHYDRATE, &record.group_id, &message);
            None
        }
        Err(error) => {
            dlog::write(
                LogLevel::Warn,
                kinds::REHYDRATE,
                &record.group_id,
                &format!("MLS snapshot unreadable: {error}"),
            );
            None
        }
    }
}

fn restore_result<T, E: std::fmt::Display>(
    group_id: &str,
    stage: &str,
    result: Result<T, E>,
) -> Option<T> {
    result
        .inspect_err(|error| {
            dlog::write(
                LogLevel::Error,
                kinds::REHYDRATE,
                group_id,
                &format!("{stage}: {error}"),
            );
        })
        .ok()
}
