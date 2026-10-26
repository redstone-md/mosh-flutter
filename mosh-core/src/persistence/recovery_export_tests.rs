use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::HistoryKey;
use crate::test_temp_directory::TempDirectory;
use serde::Serialize;

#[derive(Serialize)]
struct Lease {
    expires_ms: u64,
}

#[derive(Serialize)]
struct SelectedLease {
    expires_ms: u64,
    manifest: crate::conversation::recovery::manifest::Manifest,
}

#[test]
fn only_sixteen_frozen_sources_are_retained_and_an_expired_lease_releases_capacity() {
    let directory = TempDirectory::new("bounded-history-exports");
    let store = Persistence::open_with_dek(&directory.path().join("history"), [45; 32]).unwrap();
    let freeze = |index: usize, expires_ms: u64| {
        store.freeze_recovery(
            CHANNEL_HISTORY,
            "bounded",
            FrozenExport {
                prefix: &format!("channel:bounded\u{1}export-data\u{1}{index:064}"),
                meta_key: &format!("channel:bounded\u{1}export-meta\u{1}{index:064}"),
                header: &Lease { expires_ms },
                manifest: &store.recovery_manifest(
                    CHANNEL_HISTORY,
                    "bounded",
                    |_: &StoredMessage<String>| Ok(None::<HistoryKey>),
                )?,
            },
            |_: &StoredMessage<String>| Ok(None::<HistoryKey>),
            std::iter::empty(),
        )
    };
    let expiry = crate::conversation::now_ms() + 120_000;
    for index in 0..16 {
        freeze(index, expiry).unwrap();
    }
    assert!(freeze(16, expiry).is_err());
    let old_data = format!(
        "channel:bounded\u{1}export-data\u{1}{:064}\u{1}keys\u{1}old",
        0
    );
    store.save_recovery(&old_data, &"stale source key").unwrap();
    store
        .save_recovery(
            &format!("channel:bounded\u{1}export-meta\u{1}{:064}", 0),
            &Lease { expires_ms: 0 },
        )
        .unwrap();
    freeze(16, expiry).unwrap();
    assert!(store.recovery_state::<String>(&old_data).unwrap().is_none());
    assert!(freeze(17, expiry).is_err());
    let replaced_data = format!(
        "channel:bounded\u{1}export-data\u{1}{:064}\u{1}keys\u{1}old",
        16
    );
    store
        .save_recovery(&replaced_data, &"previous source round")
        .unwrap();
    freeze(16, expiry).unwrap();
    assert!(store
        .recovery_state::<String>(&replaced_data)
        .unwrap()
        .is_none());
}

#[test]
fn a_changed_source_refuses_the_selected_manifest_without_leaving_an_export() {
    let directory = TempDirectory::new("stale-history-offer");
    let store = Persistence::open_with_dek(&directory.path().join("history"), [46; 32]).unwrap();
    append(&store, "first", 100);
    let selected = SelectedLease {
        expires_ms: crate::conversation::now_ms() + 120_000,
        manifest: store
            .recovery_manifest(CHANNEL_HISTORY, "changed", key)
            .unwrap(),
    };
    append(&store, "later", 200);
    let meta = "channel:changed\u{1}export-meta\u{1}holder";
    assert!(
        store
            .freeze_recovery(
                CHANNEL_HISTORY,
                "changed",
                FrozenExport {
                    prefix: "channel:changed\u{1}export-data\u{1}holder",
                    meta_key: meta,
                    header: &selected,
                    manifest: &selected.manifest
                },
                key,
                std::iter::empty(),
            )
            .is_err(),
        "a first Pull must freeze exactly its Offer or refuse it"
    );
    assert!(store
        .recovery_state::<serde_json::Value>(meta)
        .unwrap()
        .is_none());
}

fn key(row: &StoredMessage<String>) -> Result<Option<HistoryKey>, String> {
    Ok(Some(HistoryKey {
        message_id: row.message_id.clone(),
        sent_at_ms: row.sent_at_ms,
        digest: crate::conversation::recovery::manifest::digest(&row.message)?,
    }))
}

fn append(store: &Persistence, id: &str, sent_at_ms: u64) {
    let row = StoredMessage {
        conversation_id: "changed".into(),
        message_id: id.into(),
        sent_at_ms,
        message: id.to_owned(),
        attachment_manifest: None,
        preview_manifest: None,
        history_evidence: None,
    };
    store
        .append_history_message(
            CHANNEL_HISTORY,
            "changed",
            sent_at_ms,
            id,
            &serde_json::to_vec(&row).unwrap(),
        )
        .unwrap();
}
