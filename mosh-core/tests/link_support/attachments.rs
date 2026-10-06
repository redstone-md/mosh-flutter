use mosh_core::api::conversation::{
    BridgeAttachmentPayload, BridgeConversationKind as Kind, BridgeConversationRef as Ref,
};
use mosh_core::api::{channel, conversation, private_group};
use mosh_core::channel_runtime::JoinChannelRequest;
use mosh_core::private_group_runtime::{CreateGroupRequest, JoinGroupRequest};
use serde_json::{json, Value};

pub(super) fn command(action: &str, argument: &str, command: &Value) -> Value {
    if action.starts_with("chat_") {
        return chat(action, argument, command);
    }
    let reference = Ref {
        kind: kind(command),
        id: argument.into(),
    };
    let result = match action {
        "attachment_send" => conversation::send_attachment(
            reference,
            BridgeAttachmentPayload {
                file_name: "screenshot.png".into(),
                mime: "image/png".into(),
                data_base64: command["data"].as_str().unwrap().into(),
                thumbnail_base64: command["miniature"].as_str().map(str::to_owned),
                preview_base64: command["preview"].as_str().map(str::to_owned),
                voice: None,
            },
        ),
        "attachment_delete" => conversation::deletion::delete_messages(
            reference,
            vec![command["message_id"].as_str().unwrap().into()],
            conversation::deletion::DeleteScope::ForMe,
        )
        .map(|_| ()),
        "attachment_download" => conversation::download_attachment(
            reference,
            command["attachment_id"].as_str().unwrap().into(),
        ),
        _ => panic!("unknown attachment command"),
    };
    match result {
        Ok(()) => json!({}),
        Err(error) => json!({"error": format!("{:?}", error.kind)}),
    }
}

fn kind(command: &Value) -> Kind {
    match command["kind"].as_str().unwrap() {
        "dm" => Kind::Dm,
        "group" => Kind::Group,
        "channel" => Kind::Channel,
        _ => panic!("unknown conversation kind"),
    }
}

fn chat(action: &str, argument: &str, command: &Value) -> Value {
    match action {
        "chat_create" => serde_json::to_value(
            private_group::create_group(CreateGroupRequest {
                label: Some("Preview test".into()),
                display_name: "Sender".into(),
                listen_port: 0,
                static_peer: None,
                org_pubkey: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "chat_join" if kind(command) == Kind::Group => serde_json::to_value(
            private_group::join_group(JoinGroupRequest {
                invite_uri: argument.into(),
                display_name: "Receiver".into(),
                listen_port: 0,
                static_peer: None,
                org_pubkey: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "chat_join" => serde_json::to_value(
            channel::join(JoinChannelRequest {
                name: argument.into(),
                display_name: "Channel peer".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "chat_poll" => match kind(command) {
            Kind::Dm => serde_json::to_value(
                mosh_core::api::private_dm::poll_session(argument.into()).unwrap(),
            )
            .unwrap(),
            Kind::Group => {
                serde_json::to_value(private_group::poll(argument.into()).unwrap()).unwrap()
            }
            Kind::Channel => serde_json::to_value(channel::poll(argument.into()).unwrap()).unwrap(),
        },
        _ => panic!("unknown chat command"),
    }
}
