//! OS work reads are bounded independently of retained historical Send admissions.
use super::*;
use serde::{Deserialize, Serialize};

const CURRENT: &str = "transfer-current/";
#[derive(Serialize, Deserialize)]
struct Current {
    view: UserTransfer,
    updated_ms: u64,
}

impl Persistence {
    /// Repair pre-index live admissions once during installation-owner startup.
    /// Historical quiescent Send records remain outside the OS work set.
    pub(crate) fn restore_current_transfer_index(&self) -> Result<(), PersistenceError> {
        let present: std::collections::BTreeSet<_> = self
            .current_user_transfers()?
            .into_iter()
            .map(|view| view.id)
            .collect();
        let missing: Vec<_> = self
            .user_transfers()?
            .into_iter()
            .filter(|view| {
                matches!(
                    view.state,
                    State::Running | State::WaitingExecution | State::Paused
                ) && !present.contains(&view.id)
            })
            .collect();
        if missing.is_empty() {
            return Ok(());
        }
        self.write(|tx| {
            for view in missing {
                self.write_current_transfer(tx, &view)?;
            }
            Ok(())
        })
    }

    pub(crate) fn current_user_transfers(&self) -> Result<Vec<UserTransfer>, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        rows.range(CURRENT.."transfer-current0")
            .map_err(db_error)?
            .map(|row| {
                let (_, bytes) = row.map_err(db_error)?;
                let current: Current = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
                Ok(current.view)
            })
            .collect()
    }

    pub(super) fn write_current_transfer(
        &self,
        tx: &redb::WriteTransaction,
        view: &UserTransfer,
    ) -> Result<(), PersistenceError> {
        let current = Current {
            view: view.clone(),
            updated_ms: crate::conversation::now_ms(),
        };
        Self::update_row(
            tx,
            BACKGROUND_DELIVERY,
            &format!("{CURRENT}{}", view.id),
            Some(&encrypt_blob(&self.dek, &encode(&current)?)?),
        )?;
        if !quiescent(view.state) {
            return Ok(());
        }
        let mut quiet = {
            let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
            let mut quiet = Vec::new();
            for row in rows.range(CURRENT.."transfer-current0").map_err(db_error)? {
                let (key, bytes) = row.map_err(db_error)?;
                let row: Current = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
                if quiescent(row.view.state) && row.view.id != view.id {
                    quiet.push((row.updated_ms, key.value().to_owned()));
                }
            }
            quiet
        };
        quiet.sort();
        let excess = quiet.len().saturating_sub(63);
        for (_, key) in quiet.into_iter().take(excess) {
            Self::update_row(tx, BACKGROUND_DELIVERY, &key, None)?;
        }
        Ok(())
    }

    pub(super) fn remove_current_transfer(
        tx: &redb::WriteTransaction,
        id: &str,
    ) -> Result<(), PersistenceError> {
        Self::update_row(tx, BACKGROUND_DELIVERY, &format!("{CURRENT}{id}"), None)
    }
}

fn quiescent(state: State) -> bool {
    !matches!(
        state,
        State::Running | State::WaitingExecution | State::Paused
    )
}
