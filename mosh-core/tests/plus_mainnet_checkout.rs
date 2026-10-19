#[path = "support/temp_directory.rs"]
mod temp_directory;

use mosh_core::{persistence::Persistence, plus::PlusRuntime};
use std::sync::Arc;
use temp_directory::TempDirectory;

#[test]
fn checkout_resumes_one_durable_request_after_restart_and_waits_for_series_agreement() {
    let directory = TempDirectory::new("mosh-mainnet-checkout");
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/plus-mainnet-public-vector.json")).unwrap();
    let path = directory.path().join("history");
    let open = || {
        PlusRuntime::open_mainnet(
            Arc::new(Persistence::open_with_dek(&path, [42; 32]).unwrap()),
            "ab".repeat(32),
            vector["public_key"].as_str().unwrap(),
            "founder",
        )
        .unwrap()
    };
    let mut owner = open();
    assert!(owner.prepare_checkout("USDC").is_err());
    owner
        .reconcile_plus_roster("roster", "founder", &["founder".into()])
        .unwrap();
    let series = owner.prepare_series().unwrap();
    owner.confirm_series_registered(&series.id).unwrap();
    let intent = owner.prepare_checkout("USDC").unwrap();
    drop(owner);
    let mut owner = open();
    let resumed = owner.prepare_checkout("USDC").unwrap();
    assert_eq!(intent.request_id, resumed.request_id);
    assert_eq!(resumed.asset, "USDC");
    assert!(owner.prepare_checkout("CLXAI").is_err());
    assert!(owner.prepare_checkout("FAKE").is_err());
    owner.cancel_checkout().unwrap();
    let replacement = owner.prepare_checkout("CLXAI").unwrap();
    assert_ne!(replacement.request_id, intent.request_id);
    assert_eq!(replacement.asset, "CLXAI");
}
