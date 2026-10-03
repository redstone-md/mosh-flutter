use std::sync::Arc;

use mosh_core::attachment_store::AttachmentStore;
use mosh_core::moss_ffi::MossFfiRuntime;
use mosh_core::private_group_runtime::PrivateGroupRuntime;

#[path = "support/temp_directory.rs"]
mod temp_directory;
use temp_directory::TempDirectory;

#[test]
fn external_caller_can_list_groups_through_public_runtime() {
    let dir = TempDirectory::new("mosh-group-interface");
    let path = dir.path().to_path_buf();
    let moss = Arc::new(MossFfiRuntime::load_default().expect("real Moss library should load"));
    let store = Arc::new(AttachmentStore::new(dir.path()).expect("attachment store should open"));
    let mut groups = PrivateGroupRuntime::from_shared(moss, store, None);

    assert!(groups
        .list()
        .expect("group list should load")
        .groups
        .is_empty());

    drop(groups);
    drop(dir);
    assert!(
        !path.exists(),
        "test attachment directory should be removed"
    );
}

#[test]
fn attachment_directory_is_removed_when_test_setup_unwinds() {
    let mut path = None;
    let failure = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let dir = TempDirectory::new("mosh-group-interface-unwind");
        path = Some(dir.path().to_path_buf());
        let _store = AttachmentStore::new(dir.path()).expect("attachment store should open");
        let _handle = std::fs::File::create(dir.path().join("open-file"))
            .expect("test file should remain open until unwind");
        panic!("simulated setup failure after opening the store");
    }));

    assert!(failure.is_err());
    assert!(
        !path.expect("directory should have been created").exists(),
        "unwind should close handles before removing the directory"
    );
}

#[test]
fn cleanup_refusal_fails_normally_and_preserves_an_existing_panic() {
    for unwinding in [false, true] {
        let dir = TempDirectory::new("mosh-group-interface-cleanup-refusal");
        let path = dir.path().to_path_buf();
        std::fs::remove_dir(&path).unwrap();
        std::fs::write(&path, b"replaced directory").unwrap();
        let failure = std::panic::catch_unwind(move || {
            let _dir = dir;
            if unwinding {
                panic!("original setup failure");
            }
        });
        std::fs::remove_file(path).expect("cleanup fault should be removed");

        let panic = failure.expect_err("cleanup refusal must not hide a test failure");
        if unwinding {
            assert_eq!(
                panic.downcast_ref::<&str>(),
                Some(&"original setup failure")
            );
        } else {
            assert!(panic
                .downcast_ref::<String>()
                .unwrap()
                .contains("test directory cleanup failed"));
        }
    }
}
