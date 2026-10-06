use super::*;

#[test]
fn a_same_size_corrupted_cached_original_is_not_restored_or_streamed() {
    let scratch = Scratch::open("restore-corrupted-original");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "cached", vec![1, 2, 3, 4]);
    let descriptor = descriptor_of(&manifest);
    let path = scratch
        .store
        .path_for(&descriptor.content_hash, &descriptor.file_name)
        .unwrap();
    std::fs::write(path, [4, 3, 2, 1]).unwrap();

    let mut legacy = scratch.transfer();
    legacy.restore_cached(&descriptor, AttachmentDirection::Outgoing);
    assert!(!legacy.holds("cached"));
    assert!(matches!(
        legacy.stream_range("cached", 0, 4),
        StreamRange::Unknown
    ));

    let mut incoming = scratch.transfer();
    incoming.restore_stored(&descriptor, AttachmentDirection::Incoming, Some(manifest));
    assert_eq!(state_of(&incoming, "cached"), AttachmentState::Offered);
    assert!(!matches!(
        incoming.stream_range("cached", 0, 4),
        StreamRange::Ready { .. }
    ));
}
