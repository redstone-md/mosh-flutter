use super::*;
use crate::test_temp_directory::TempDirectory;

fn import_last_counter(store: Arc<Persistence>) -> ChatNames {
    let mut names = ChatNames::open(store, "user", "local").unwrap();
    names
        .merge(
            &[NameRecord {
                key: "channel:general".into(),
                name: Some("Imported".into()),
                version: NameVersion {
                    counter: u64::MAX - 1,
                    actor: "peer".into(),
                },
            }],
            true,
        )
        .unwrap();
    names
}

#[test]
fn the_last_u64_version_can_rename_and_replicate_without_wrapping() {
    let dir = TempDirectory::new("mosh-name-counter");
    let store = Arc::new(Persistence::open_with_dek(&dir.path().join("db"), [13; 32]).unwrap());
    let mut names = import_last_counter(store.clone());
    names.rename("channel:general", "Last rename").unwrap();
    let last = names.page(None);
    assert_eq!(last[0].version.counter, u64::MAX);
    let mut replica = ChatNames::open(store.clone(), "replica", "other").unwrap();
    replica.merge(&last, true).unwrap();
    assert_eq!(replica.name("channel:general"), Some("Last rename"));
    let mut restored = ChatNames::open(store, "user", "local").unwrap();
    assert_eq!(restored.name("channel:general"), Some("Last rename"));
    assert_eq!(
        restored
            .rename("channel:general", "Would wrap")
            .unwrap_err()
            .kind,
        ChatNameErrorKind::InvalidInput
    );
    assert_eq!(restored.page(None), last);
}

#[test]
fn the_last_u64_version_can_reset_and_survives_restart() {
    let dir = TempDirectory::new("mosh-name-reset-counter");
    let store = Arc::new(Persistence::open_with_dek(&dir.path().join("db"), [14; 32]).unwrap());
    let mut names = import_last_counter(store.clone());
    names.reset("channel:general").unwrap();
    assert_eq!(names.page(None)[0].version.counter, u64::MAX);
    let restored = ChatNames::open(store, "user", "local").unwrap();
    assert_eq!(restored.name("channel:general"), None);
    assert_eq!(restored.page(None)[0].version.counter, u64::MAX);
}
