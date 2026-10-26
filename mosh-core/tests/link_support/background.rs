//! Approved background bridge commands, exercised without a Flutter/widget owner.
use mosh_core::api::background;
use serde_json::{json, Value};

pub(super) fn command(action: &str, request: &Value) -> Value {
    match action {
        "background_set" => serde_json::to_value(
            background::set_background_execution(
                request["interactive"].as_bool().unwrap(),
                request["waiting"].as_bool().unwrap(),
            )
            .unwrap(),
        )
        .unwrap(),
        "background_status" => {
            serde_json::to_value(background::background_status().unwrap()).unwrap()
        }
        "background_pending" => {
            serde_json::to_value(background::pending_background_notifications(16).unwrap()).unwrap()
        }
        "background_ack" => {
            background::ack_background_notification(
                request["id"].as_str().unwrap().into(),
                request["revision"].as_u64().unwrap(),
            )
            .unwrap();
            json!({})
        }
        _ => panic!("unknown background bridge command"),
    }
}
