use mosh_core::api::{channel, plus, private_group};
use mosh_core::channel_runtime::JoinChannelRequest;
use mosh_core::private_group_runtime::{CreateGroupRequest, JoinGroupRequest};
use serde_json::{json, Value};

pub(super) fn command(action: &str, argument: &str, input: &Value) -> Value {
    let result = match action {
        "plus_configure" => plus::configure_issuer(argument.into()),
        "plus_snapshot" => plus::snapshot(),
        "plus_order" => plus::save_order(argument.into()),
        "plus_complete" => plus::complete_issuance(argument.into()),
        "plus_visible" => plus::set_visible(input["visible"].as_bool().unwrap()),
        "plus_prepare" => return json!({"blinded":plus::prepare_issuance().unwrap()}),
        _ => return conversations(action, argument),
    };
    match result {
        Ok(snapshot) => serde_json::to_value(snapshot).unwrap(),
        Err(error) => json!({"error":error}),
    }
}

fn conversations(action: &str, argument: &str) -> Value {
    match action {
        "plus_channel_poll" => {
            serde_json::to_value(channel::poll(argument.into()).unwrap()).unwrap()
        }
        "plus_channel" => serde_json::to_value(
            channel::join(JoinChannelRequest {
                name: argument.into(),
                display_name: "Plus tester".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "plus_group_create" => serde_json::to_value(
            private_group::create_group(CreateGroupRequest {
                label: Some("Plus test".into()),
                display_name: "Plus tester".into(),
                org_pubkey: None,
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "plus_group_join" => serde_json::to_value(
            private_group::join_group(JoinGroupRequest {
                invite_uri: argument.into(),
                display_name: "Plus reader".into(),
                org_pubkey: None,
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "plus_group_poll" => {
            serde_json::to_value(private_group::poll(argument.into()).unwrap()).unwrap()
        }
        _ => panic!("unknown PLUS test command"),
    }
}
