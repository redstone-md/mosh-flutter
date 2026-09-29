use super::{store::ResumptionPskStore, *};

fn add(store: &mut ResumptionPskStore, epoch: u64) {
    let secret = ResumptionPskSecret {
        secret: Secret::from_slice(&[epoch as u8; 32]),
    };
    store.add(epoch.into(), secret);
}

fn assert_recent_epochs(store: &ResumptionPskStore, last: u64, capacity: usize) {
    for epoch in 0..=last {
        let expected = capacity > 0 && last - epoch < capacity as u64;
        assert_eq!(
            store.get(epoch.into()).is_some(),
            expected,
            "epoch {epoch}, last {last}"
        );
    }
}

#[test]
fn rollover_retains_recent_epochs_across_reload() {
    for capacity in [0, 1, 3] {
        let mut store = ResumptionPskStore::new(capacity);
        for epoch in 0..10 {
            add(&mut store, epoch);
            assert_recent_epochs(&store, epoch, capacity);
            store = serde_json::from_slice(&serde_json::to_vec(&store).unwrap()).unwrap();
        }
    }
}

#[test]
fn legacy_full_cursor_before_first_rollover() {
    let mut store = ResumptionPskStore::new(3);
    for epoch in 0..3 {
        add(&mut store, epoch);
    }
    let mut legacy = serde_json::to_value(&store).unwrap();
    legacy["cursor"] = 3.into();
    let mut restored = serde_json::from_value(legacy).unwrap();
    add(&mut restored, 3);
    assert_recent_epochs(&restored, 3, 3);
}

#[test]
fn legacy_store_after_incorrect_rollover_evicts_oldest_epoch() {
    let mut store = ResumptionPskStore::new(3);
    for epoch in [0, 3, 2] {
        add(&mut store, epoch);
    }
    let mut legacy = serde_json::to_value(&store).unwrap();
    legacy["cursor"] = 1.into();
    let mut restored = serde_json::from_value(legacy).unwrap();
    add(&mut restored, 4);
    assert_recent_epochs(&restored, 4, 3);
}
