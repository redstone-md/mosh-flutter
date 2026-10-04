use std::io::{BufRead, Write};
use std::path::PathBuf;

use mosh_core::api::{conversation, device_link, private_dm};
use mosh_core::private_dm_runtime::{AcceptInviteRequest, StartSessionRequest};
use serde_json::{json, Value};

use super::OUTPUT_PREFIX;

/// Exercise the public bridge facade with real shared resources and discovery.
pub(super) fn run(dir: PathBuf) {
    private_dm::set_app_data_dir(dir.to_string_lossy().into_owned()).unwrap();
    private_dm::set_history_dek(std::fs::read(dir.join("storage-key.bin")).unwrap()).unwrap();
    for line in std::io::stdin().lock().lines() {
        let command: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let argument = command["argument"].as_str().unwrap_or_default().to_owned();
        let action = command["action"].as_str().unwrap();
        if action.starts_with("dm_") {
            println!("{OUTPUT_PREFIX}{}", dm_command(action, argument, &command));
            std::io::stdout().flush().unwrap();
            continue;
        }
        if matches!(action, "names" | "name_set" | "name_reset") {
            println!(
                "{OUTPUT_PREFIX}{}",
                names_command(action, &argument, &command)
            );
            std::io::stdout().flush().unwrap();
            continue;
        }
        let result = match command["action"].as_str().unwrap() {
            "shutdown" => break,
            "snapshot" => device_link::snapshot(),
            "qr" => device_link::begin_link(),
            "import" => device_link::join_link(
                argument,
                command["name"].as_str().unwrap_or_default().into(),
            ),
            "approve" => device_link::approve(argument),
            "cancel" => device_link::cancel(),
            "revoke" => device_link::revoke(argument),
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

fn dm_command(action: &str, argument: String, command: &Value) -> Value {
    match action {
        "dm_invite" => serde_json::to_value(
            private_dm::create_invite(StartSessionRequest {
                display_name: "Original desktop".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "dm_accept" => serde_json::to_value(
            private_dm::accept_invite(AcceptInviteRequest {
                display_name: "Counterpart".into(),
                invite_uri: argument,
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "dm_list" => serde_json::to_value(private_dm::list_sessions().unwrap()).unwrap(),
        "dm_poll" => serde_json::to_value(private_dm::poll_session(argument).unwrap()).unwrap(),
        "dm_send" => {
            conversation::send(
                conversation::BridgeConversationRef {
                    kind: conversation::BridgeConversationKind::Dm,
                    id: argument,
                },
                command["body"].as_str().unwrap().into(),
            )
            .unwrap();
            json!({})
        }
        _ => panic!("unknown bridge DM command"),
    }
}

fn names_command(action: &str, argument: &str, command: &Value) -> Value {
    use conversation::{BridgeConversationKind as Kind, BridgeConversationRef as Ref};
    let result = if action == "names" {
        conversation::names::personal_names()
    } else {
        let (kind, id) = argument.split_once(':').unwrap();
        let reference = Ref {
            kind: match kind {
                "dm" => Kind::Dm,
                "channel" => Kind::Channel,
                "group" => Kind::Group,
                _ => panic!("invalid conversation kind"),
            },
            id: id.into(),
        };
        let accepted = if action == "name_set" {
            conversation::names::rename(reference, command["name"].as_str().unwrap().into())
        } else {
            conversation::names::reset_name(reference)
        };
        accepted.and_then(|_| conversation::names::personal_names())
    };
    match result {
        Ok(snapshot) => serde_json::to_value(snapshot).unwrap(),
        Err(error) => json!({"error":format!("{:?}", error.kind)}),
    }
}
