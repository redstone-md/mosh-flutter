use std::sync::Arc;

use mosh_core::attachment_store::AttachmentStore;
use mosh_core::moss_ffi::MossFfiRuntime;
use mosh_core::private_group_runtime::PrivateGroupRuntime;

#[test]
fn external_caller_can_list_groups_through_public_runtime() {
    let dir = std::env::temp_dir().join(format!("mosh-group-interface-{}", rand::random::<u64>()));
    let moss = Arc::new(MossFfiRuntime::load_default().expect("real Moss library should load"));
    let store = Arc::new(AttachmentStore::new(&dir).expect("attachment store should open"));
    let mut groups = PrivateGroupRuntime::from_shared(moss, store, None);

    assert!(groups
        .list()
        .expect("group list should load")
        .groups
        .is_empty());

    drop(groups);
    std::fs::remove_dir_all(dir).expect("test attachment directory should be removed");
}
