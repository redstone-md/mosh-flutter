#[path = "support/temp_directory.rs"]
mod temp_directory;

use std::sync::Arc;

use mosh_core::chat_names::ChatNames;
use mosh_core::persistence::Persistence;
use temp_directory::TempDirectory;

#[test]
fn private_chat_names_and_resets_survive_restart_without_changing_history() {
    let dir = TempDirectory::new("mosh-chat-names");
    let path = dir.path().join("history.redb");
    let db = Arc::new(Persistence::open_with_dek(&path, [73; 32]).unwrap());
    db.put_session("dm-1", b"original contact").unwrap();
    let mut names = ChatNames::open(db.clone(), "user-1", "device-1").unwrap();
    names.rename("dm:dm-1", "  Мама  ").unwrap();
    names.rename("channel:general", "Работа").unwrap();
    drop(names);
    drop(db);

    let db = Arc::new(Persistence::open_with_dek(&path, [73; 32]).unwrap());
    let mut names = ChatNames::open(db.clone(), "user-1", "device-1").unwrap();
    assert_eq!(names.name("dm:dm-1"), Some("Мама"));
    assert_eq!(names.name("channel:general"), Some("Работа"));
    names.reset("dm:dm-1").unwrap();
    drop(names);
    assert_eq!(
        db.list_sessions().unwrap(),
        vec![b"original contact".to_vec()]
    );
    let names = ChatNames::open(db, "user-1", "device-1").unwrap();
    assert_eq!(names.name("dm:dm-1"), None);
    assert_eq!(names.name("channel:general"), Some("Работа"));
}

#[test]
fn invalid_names_never_replace_a_saved_name_or_escape_the_account() {
    let dir = TempDirectory::new("mosh-name-validation");
    let db = Arc::new(Persistence::open_with_dek(&dir.path().join("db"), [13; 32]).unwrap());
    let mut names = ChatNames::open(db.clone(), "user-1", "device-1").unwrap();
    names.rename("channel:general", "Работа").unwrap();
    for invalid in [
        "",
        "  ",
        "Bad\nName",
        "Bad\u{2028}Name",
        "Bad\0Name",
        &"я".repeat(65),
    ] {
        assert!(names.rename("channel:general", invalid).is_err());
        assert_eq!(names.name("channel:general"), Some("Работа"));
    }
    assert!(names
        .rename("group:group-1", "Private group alias")
        .is_err());
    assert_eq!(
        ChatNames::open(db, "other-user", "device-2")
            .unwrap()
            .name("channel:general"),
        None
    );
}
