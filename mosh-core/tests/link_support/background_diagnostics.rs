//! Failed background probes stop before UI polling, then inspect only a copy.
use super::Peer;
use redb::{ReadableTable, TableDefinition};
use serde_json::{json, Value};
use std::path::Path;
use std::time::{Duration, Instant};

impl Peer {
    /// Observe only the durable queue; preserve failed reception before any UI poll.
    #[allow(dead_code, reason = "Shared independent-installation harness.")]
    pub fn wait_background_dm(&mut self, sender: &mut Peer, id: &str) -> Value {
        let deadline = Instant::now() + Duration::from_secs(90);
        loop {
            let pending = self.ask(json!({"action":"background_pending"}));
            if pending
                .as_array()
                .is_some_and(|entries| !entries.is_empty())
            {
                return pending;
            }
            if Instant::now() >= deadline {
                let stored = self.stop_and_inspect_background("dm", id);
                // The recipient is already stopped: this cannot drive reception.
                let sent = sender.ask(json!({"action":"dm_poll","argument":id}));
                let statuses: Vec<_> = sent["messages"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|row| row["body"] == "private background text")
                    .map(|row| row["delivery_status"].clone())
                    .collect();
                panic!("background DM missing; receiver before poll: {stored}; sender after receiver stop: state={}, delivery={statuses:?}", sent["state"]);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }

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
            "group_history_basis":row["history_evidence"]["group"]["basis"],
            "has_offer": !row["attachment_manifest"].is_null(),
            "has_preview": !row["preview_manifest"].is_null(),
            "background_fixture_text":message["body"] == "New background text"
                || message["body"] == "private background text",
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
