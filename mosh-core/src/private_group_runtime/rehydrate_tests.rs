use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::test_temp_directory::TempDirectory;

fn identity() -> Vec<u8> {
    let seed = [83; 32];
    let key = SigningKey::from_bytes(&seed);
    let mut blob = vec![1];
    blob.extend_from_slice(&seed);
    blob.extend_from_slice(&key.verifying_key().to_bytes());
    blob.extend_from_slice(&[0; 64]);
    blob
}

#[test]
fn an_unavailable_org_signer_does_not_acquire_a_room_during_restore() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    crate::moss_ffi::drain_received_messages();
    let directory = TempDirectory::new("mosh-group-signer-restore");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [84; 32]).unwrap(),
    );
    store.put_moss_identity(&identity()).unwrap();
    let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    let id = {
        let mut creator = PrivateGroupRuntime::from_shared(
            moss.clone(),
            attachments.clone(),
            Some(store.clone()),
        );
        creator
            .create_group(CreateGroupRequest {
                label: None,
                display_name: "Alice".into(),
                listen_port: 0,
                static_peer: None,
                org_pubkey: Some("a".repeat(64)),
            })
            .unwrap()
            .group_id
    };
    store.put_moss_identity(b"corrupt node identity").unwrap();
    let shared = SharedMossNode::new(moss);
    let mut restored =
        PrivateGroupRuntime::from_shared_node(shared.clone(), attachments, Some(store.clone()));
    restored.rehydrate();
    assert!(restored.list().unwrap().groups.is_empty());
    assert!(shared.current().is_none());
    store.put_moss_identity(&identity()).unwrap();
    restored.rehydrate();
    assert_eq!(restored.poll(&id).unwrap().member_count, 1);
}
