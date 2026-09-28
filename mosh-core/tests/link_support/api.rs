use std::io::{BufRead, Write};
use std::path::PathBuf;

use mosh_core::api::{device_link, private_dm};
use serde_json::{json, Value};

use super::OUTPUT_PREFIX;

/// Exercise the public bridge facade with real shared resources and discovery.
pub(super) fn run(dir: PathBuf) {
    private_dm::set_app_data_dir(dir.to_string_lossy().into_owned()).unwrap();
    private_dm::set_history_dek(vec![91; 32]).unwrap();
    for line in std::io::stdin().lock().lines() {
        let command: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let argument = command["argument"].as_str().unwrap_or_default().to_owned();
        let result = match command["action"].as_str().unwrap() {
            "shutdown" => break,
            "snapshot" => device_link::snapshot(),
            "qr" => device_link::create_qr(argument),
            "import" => device_link::import_qr(argument),
            "approve" => device_link::approve(argument),
            "cancel" => device_link::cancel(),
            _ => panic!("unknown bridge command"),
        };
        let response = match result {
            Ok(snapshot) => serde_json::to_value(snapshot).unwrap(),
            Err(error) => json!({"error":error.kind}),
        };
        println!("{OUTPUT_PREFIX}{response}");
        std::io::stdout().flush().unwrap();
    }
}
