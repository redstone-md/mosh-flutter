use super::fragment_buffer::{split_bytes, FragmentBuffer};

#[test]
fn large_pages_survive_reordered_and_duplicate_fragments() {
    let bytes: Vec<_> = (0..90_001).map(|i| (i % 251) as u8).collect();
    let fragments = split_bytes(&bytes).unwrap();
    let mut buffer = FragmentBuffer::default();
    assert!(buffer.add("peer", fragments[1].clone()).unwrap().is_none());
    assert!(buffer.add("peer", fragments[1].clone()).unwrap().is_none());
    let mut received = None;
    for fragment in fragments.into_iter().rev() {
        if let Some(page) = buffer.add("peer", fragment).unwrap() {
            received = Some(page);
        }
    }
    assert_eq!(received, Some(bytes));
}

#[test]
fn different_carriers_cannot_complete_each_others_pages() {
    let fragments = split_bytes(&vec![42; 4500]).unwrap();
    let mut buffer = FragmentBuffer::default();
    assert!(buffer.add("alice", fragments[0].clone()).unwrap().is_none());
    assert!(buffer.add("bob", fragments[1].clone()).unwrap().is_none());
    assert_eq!(
        buffer.add("alice", fragments[1].clone()).unwrap(),
        Some(vec![42; 4500])
    );
}

#[test]
fn conflicting_and_oversized_fragments_are_rejected() {
    let fragments = split_bytes(&vec![42; 4500]).unwrap();
    let mut buffer = FragmentBuffer::default();
    buffer.add("peer", fragments[0].clone()).unwrap();
    let mut conflict = fragments[0].clone();
    conflict.bytes_b64 = crate::conversation::encode(&vec![41; 3000]);
    assert!(buffer.add("peer", conflict).is_err());
    let mut invalid = fragments[1].clone();
    invalid.total = usize::MAX;
    assert!(buffer.add("peer", invalid).is_err());
    assert!(split_bytes(&vec![0; 200_001]).is_err());
}

#[test]
fn corrupt_complete_page_is_rejected() {
    let mut fragments = split_bytes(&vec![42; 4500]).unwrap();
    fragments[1].bytes_b64 = crate::conversation::encode(&vec![41; 1500]);
    let mut buffer = FragmentBuffer::default();
    buffer.add("peer", fragments.remove(0)).unwrap();
    assert!(buffer.add("peer", fragments.remove(0)).is_err());
}
