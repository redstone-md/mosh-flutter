use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::HistoryKey;
use crate::test_temp_directory::TempDirectory;
use serde::Serialize;

#[derive(Serialize)]
struct Lease {
    expires_ms: u64,
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
    store
        .save_recovery(
            &format!("channel:bounded\u{1}export-meta\u{1}{:064}", 0),
            &Lease { expires_ms: 0 },
        )
        .unwrap();
    freeze(16, expiry).unwrap();
    assert!(freeze(17, expiry).is_err());
}
