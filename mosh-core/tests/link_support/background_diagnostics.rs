//! Failed background probes stop before UI polling, then inspect only a copy.
use super::Peer;
use redb::{ReadableTable, TableDefinition};
use serde_json::{json, Value};
use std::path::Path;

impl Peer {
    #[allow(
        dead_code,
        reason = "Manual actual-carrier acceptance failure diagnostics."
    )]
    pub fn stop_and_inspect_background(&mut self, kind: &str, id: &str) -> Value {
        self.stop();
        let path = self.dir.join("mosh/history.redb");
        let key = std::fs::read(self.dir.join("storage-key.bin")).unwrap();
        if let Some(root) = std::env::var_os("MOSH_TEST_ARTIFACT_DIR") {
            let destination =
                std::path::PathBuf::from(root).join(format!("{kind}-receiver-before-poll"));
            std::fs::create_dir_all(&destination).unwrap();
            std::fs::copy(&path, destination.join("history.redb")).unwrap();
            std::fs::write(destination.join("generated-fixture-key.bin"), &key).unwrap();
        }
        // redb2 has no read-only opener. The original remains untouched; the
        // diagnostic opens a disposable copy and performs only read transactions.
        let inspect = self.dir.join("history-inspect.redb");
        std::fs::copy(path, &inspect).unwrap();
        inspect_background(&inspect, key.try_into().unwrap(), kind, id)
    }
}

fn inspect_background(path: &Path, key: [u8; 32], kind: &str, id: &str) -> Value {
    let database = redb::Database::open(path).unwrap();
    let tx = database.begin_read().unwrap();
    let ledger = tx
        .open_table(TableDefinition::<&str, &[u8]>::new("background_delivery"))
        .unwrap();
    let control = ledger
        .get("control-v1")
        .unwrap()
        .map(|bytes| decode(&key, bytes.value()));
    let table = match kind {
        "group" => "group_messages",
        "channel" => "channel_messages",
        _ => "messages",
    };
    let history = tx
        .open_table(TableDefinition::<&str, &[u8]>::new(table))
        .unwrap();
    let prefix = format!("{id}\u{1}");
    let mut messages = Vec::new();
    for row in history.iter().unwrap() {
        let (row_key, bytes) = row.unwrap();
        if !row_key.value().starts_with(&prefix) {
            continue;
        }
        let row = decode(&key, bytes.value());
        let message = &row["message"];
        messages.push(json!({
            "message_id":message["message_id"],
            "is_own":message["metadata"]["is_own"],
            "history_basis":row["history_evidence"]["basis"],
            "background_fixture_text":message["body"] == "New background text",
        }));
    }
    let mut notifications = Vec::new();
    for row in ledger.iter().unwrap() {
        let (name, bytes) = row.unwrap();
        if !name.value().starts_with("message/") {
            continue;
        }
        let row = decode(&key, bytes.value());
        if row["target"]["id"] == id {
            notifications.push(
                json!({"revision":row["revision"], "message_id":row["message_id"],
                "acknowledged":row["acknowledged"], "message_count":row["message_count"]}),
            );
        }
    }
    json!({"control":control,"messages":messages,"notifications":notifications})
}

fn decode(key: &[u8; 32], bytes: &[u8]) -> Value {
    serde_json::from_slice(&mosh_core::persistence::decrypt_blob(key, bytes).unwrap()).unwrap()
}
