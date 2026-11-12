//! What a crash would leave of a step's writes.
//!
//! A crashed process leaves the file as the last sync wrote it, and a copy
//! of the file taken while the store is open is that same file. Windows
//! locks an open store against the copy, so these read it on Unix.
#![cfg(unix)]

use super::*;
use crate::test_temp_directory::TempDirectory;
use std::path::PathBuf;
use std::sync::Arc;

const DEK: [u8; 32] = [5; 32];

struct Store {
    open: Arc<Persistence>,
    directory: TempDirectory,
}

impl Store {
    fn new(name: &str) -> Self {
        let directory = TempDirectory::new(&format!("mosh-steps-{name}"));
        let open = Arc::new(Persistence::open_with_dek(&path(&directory, "live"), DEK).unwrap());
        Self { open, directory }
    }

    /// The store a restart after a crash at this moment would open.
    fn after_crash(&self) -> Persistence {
        let copy = path(
            &self.directory,
            &format!("crashed-{}", rand::random::<u64>()),
        );
        std::fs::copy(path(&self.directory, "live"), &copy).unwrap();
        Persistence::open_with_dek(&copy, DEK).unwrap()
    }
}

fn path(directory: &TempDirectory, name: &str) -> PathBuf {
    directory.path().join(format!("{name}.redb"))
}

#[test]
fn a_step_s_writes_reach_the_disk_at_its_end() {
    let store = Store::new("end");
    let step = store.open.step();
    store.open.put_org_roster("org", b"roster").unwrap();

    assert_eq!(
        store.open.get_org_roster("org").unwrap().as_deref(),
        Some(&b"roster"[..]),
        "the step reads its own write"
    );
    assert_eq!(store.after_crash().get_org_roster("org").unwrap(), None);

    drop(step);

    assert_eq!(
        store
            .after_crash()
            .get_org_roster("org")
            .unwrap()
            .as_deref(),
        Some(&b"roster"[..])
    );
}

#[test]
fn a_sync_puts_a_step_s_earlier_writes_on_disk() {
    let store = Store::new("sync");
    let _step = store.open.step();
    store.open.put_org_roster("before", b"roster").unwrap();

    store.open.sync().unwrap();
    store.open.put_org_roster("after", b"roster").unwrap();

    let crashed = store.after_crash();
    assert!(crashed.get_org_roster("before").unwrap().is_some());
    assert_eq!(crashed.get_org_roster("after").unwrap(), None);
}

#[test]
fn a_step_inside_a_step_ends_with_the_outer_one() {
    let store = Store::new("nested");
    let outer = store.open.step();
    let inner = store.open.step();
    store.open.put_org_roster("org", b"roster").unwrap();

    drop(inner);
    assert_eq!(store.after_crash().get_org_roster("org").unwrap(), None);

    drop(outer);
    assert!(store.after_crash().get_org_roster("org").unwrap().is_some());
}

#[test]
fn a_write_outside_a_step_reaches_the_disk_at_once_with_every_step_s_writes() {
    let store = Store::new("outside");
    let _step = store.open.step();
    store.open.put_org_roster("in a step", b"roster").unwrap();

    let other = store.open.clone();
    std::thread::spawn(move || other.put_org_roster("outside", b"roster").unwrap())
        .join()
        .unwrap();

    let crashed = store.after_crash();
    assert!(crashed.get_org_roster("outside").unwrap().is_some());
    assert!(crashed.get_org_roster("in a step").unwrap().is_some());
}
