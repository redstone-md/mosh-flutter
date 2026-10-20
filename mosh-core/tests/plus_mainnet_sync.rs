#[path = "support/temp_directory.rs"]
mod temp_directory;

use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use std::sync::Arc;
use temp_directory::TempDirectory;

#[test]
fn initial_checkout_waits_for_durable_sibling_ack_and_committed_series_survives_revocation() {
    let directory = TempDirectory::new("mosh-mainnet-bootstrap");
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let open = |device: &str| {
        PlusRuntime::open_mainnet(
            Arc::new(Persistence::open_with_dek(&directory.path().join(device), [42; 32]).unwrap()),
            "ab".repeat(32),
            vector["public_key"].as_str().unwrap(),
            device,
        )
        .unwrap()
    };
    let mut founder = open("founder");
    let mut sibling = open("sibling");
    let members = vec!["founder".into(), "sibling".into()];
    founder
        .reconcile_plus_roster("roster-1", "founder", &members)
        .unwrap();
    sibling
        .reconcile_plus_roster("roster-1", "founder", &members)
        .unwrap();
    assert!(sibling.prepare_series().is_err());
    let proposal = founder.prepare_series().unwrap();
    founder.confirm_series_registered(&proposal.id).unwrap();
    assert!(!founder.snapshot(0).checkout_ready);
    sibling
        .merge_sync(&founder.export_sync(None).unwrap().unwrap())
        .unwrap();
    drop(sibling);
    let mut sibling = open("sibling");
    sibling
        .reconcile_plus_roster("roster-1", "founder", &members)
        .unwrap();
    founder
        .acknowledge_sync("sibling", &sibling.series_digest().unwrap())
        .unwrap();
    assert!(founder.snapshot(0).checkout_ready);
    sibling
        .merge_sync(&founder.export_sync(None).unwrap().unwrap())
        .unwrap();
    assert!(sibling.snapshot(0).checkout_ready);
    let remaining = vec!["sibling".into(), "newcomer".into()];
    sibling
        .reconcile_plus_roster("roster-2", "founder", &remaining)
        .unwrap();
    assert!(sibling.snapshot(0).checkout_ready);
    let mut newcomer = open("newcomer");
    newcomer
        .reconcile_plus_roster("roster-2", "founder", &remaining)
        .unwrap();
    assert!(newcomer.prepare_series().is_err());
    newcomer
        .merge_sync(&sibling.export_sync(None).unwrap().unwrap())
        .unwrap();
    assert_eq!(newcomer.snapshot(0).series.unwrap().id, proposal.id);
    assert!(newcomer.snapshot(0).checkout_ready);
    founder
        .reconcile_plus_roster("roster-2", "founder", &remaining)
        .unwrap();
    assert!(!founder.snapshot(0).checkout_ready);
}
