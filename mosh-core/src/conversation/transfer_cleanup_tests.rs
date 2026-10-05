use super::*;
use crate::persistence::{Persistence, DM_HISTORY};

#[test]
fn a_shared_cached_file_is_removed_only_after_its_last_message() {
    let scratch = Scratch::open("deletion-shared-file");
    let mut transfer = scratch.transfer();
    let first = send(&mut transfer, "first", vec![42; 32]);
    let second = send(&mut transfer, "second", vec![42; 32]);
    let descriptor = descriptor_of(&first);
    assert_eq!(first.content_hash, second.content_hash);
    let external = scratch.dir.join("saved-by-user.bin");
    std::fs::write(&external, [42; 32]).unwrap();
    transfer.forget("first");
    assert!(!transfer.clean_erased(&descriptor, None).unwrap());
    assert!(scratch.store.exists(&first.content_hash, FILE).unwrap());
    transfer.forget("second");
    assert!(transfer.clean_erased(&descriptor, None).unwrap());
    assert!(!scratch.store.exists(&first.content_hash, FILE).unwrap());
    assert!(external.is_file());
}

#[test]
fn an_unopened_conversations_reference_preserves_a_cached_file() {
    let scratch = Scratch::open("deletion-cold-reference");
    let mut transfer = scratch.transfer();
    let manifest = send(&mut transfer, "file", vec![42; 32]);
    let descriptor = descriptor_of(&manifest);
    let store = Persistence::open_with_dek(&scratch.dir.join("history"), [7; 32]).unwrap();
    let row = serde_json::json!({"message": {"attachment": descriptor}});
    store
        .append_message("other", 1, "reference", &serde_json::to_vec(&row).unwrap())
        .unwrap();
    transfer.forget("file");
    assert!(!transfer.clean_erased(&descriptor, Some(&store)).unwrap());
    store.delete_session("other").unwrap();
    assert!(transfer.clean_erased(&descriptor, Some(&store)).unwrap());
}

#[test]
fn blocked_cache_entries_do_not_starve_later_cleanup() {
    let scratch = Scratch::open("deletion-gc-progress");
    let mut transfer = scratch.transfer();
    let store = Persistence::open_with_dek(&scratch.dir.join("history"), [7; 32]).unwrap();
    let mut descriptors = Vec::new();
    for i in 0..20 {
        let manifest = send(&mut transfer, &i.to_string(), vec![i; 32]);
        descriptors.push(descriptor_of(&manifest));
    }
    descriptors.sort_by(|a, b| a.content_hash.cmp(&b.content_hash));
    let last = descriptors.last().unwrap();
    store
        .commit_message_deletions::<serde_json::Value>(
            DM_HISTORY,
            &[],
            &[],
            &Default::default(),
            &descriptors,
        )
        .unwrap();
    transfer.forget(&last.attachment_id);
    transfer.collect_erased_cache(&store);
    transfer.collect_erased_cache(&store);
    assert!(!scratch
        .store
        .exists(&last.content_hash, &last.file_name)
        .unwrap());
    assert!(scratch
        .store
        .exists(&descriptors[0].content_hash, FILE)
        .unwrap());
}

#[test]
fn deleting_a_download_discards_late_chunks_and_stops_playback_ranges() {
    let scratch = Scratch::open("deletion-late-chunk");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "file", vec![42; 32]);
    let mut receiver = scratch.transfer();
    receiver.accept_manifest(manifest).unwrap();
    receiver.start_download("file").unwrap();
    let request = receiver.next_requests().remove(0);
    let chunk = sender.serve(&request).remove(0);
    receiver.forget("file");
    receiver.ingest(&chunk).unwrap();
    assert!(receiver.views().is_empty());
    assert!(receiver.next_requests().is_empty());
    assert!(matches!(
        receiver.stream_range("file", 0, 32),
        StreamRange::Unknown
    ));
}
