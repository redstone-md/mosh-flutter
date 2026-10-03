//! Reversible failures from real redb table validation, isolated to one store.
use super::*;
use redb::TableHandle;
use std::sync::Arc;

pub(crate) struct TableFault {
    store: Arc<Persistence>,
    table: Rows,
    rows: Vec<(String, Vec<u8>)>,
}

impl Persistence {
    pub(crate) fn refuse_message_writes(self: &Arc<Self>, tables: HistoryTables) -> TableFault {
        self.refuse_table_writes(tables.messages)
    }

    pub(crate) fn refuse_attempt_writes(self: &Arc<Self>) -> TableFault {
        self.refuse_table_writes(OUTBOUND_ATTEMPTS)
    }

    pub(crate) fn refuse_record_writes(self: &Arc<Self>, tables: HistoryTables) -> TableFault {
        self.refuse_table_writes(tables.conversations)
    }

    pub(crate) fn refuse_dm_snapshot_writes(self: &Arc<Self>) -> TableFault {
        self.refuse_table_writes(MLS_SNAPSHOT)
    }

    pub(crate) fn refuse_group_snapshot_writes(self: &Arc<Self>) -> TableFault {
        self.refuse_table_writes(GROUP_MLS_SNAPSHOT)
    }

    fn refuse_table_writes(self: &Arc<Self>, table: Rows) -> TableFault {
        let tx = self.db.begin_write().expect("fault transaction");
        let rows = tx
            .open_table(table)
            .expect("original table")
            .iter()
            .expect("original rows")
            .map(|row| {
                let (key, value) = row.expect("original row");
                (key.value().to_string(), value.value().to_vec())
            })
            .collect();
        tx.delete_table(table).expect("replace original table");
        tx.open_table(TableDefinition::<&str, u64>::new(table.name()))
            .expect("incompatible table");
        tx.commit().expect("save incompatible table");
        TableFault {
            store: Arc::clone(self),
            table,
            rows,
        }
    }
}

impl Drop for TableFault {
    fn drop(&mut self) {
        let tx = self.store.db.begin_write().expect("repair transaction");
        tx.delete_table(self.table)
            .expect("remove incompatible table");
        {
            let mut table = tx.open_table(self.table).expect("restore table");
            for (key, value) in &self.rows {
                table
                    .insert(key.as_str(), value.as_slice())
                    .expect("restore row");
            }
        }
        tx.commit().expect("save repaired table");
    }
}
