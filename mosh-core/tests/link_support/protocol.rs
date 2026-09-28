//! Independent wire fixtures with positive delivery controls. Each process
//! signs with its own stored key; only public requests leave that process.
use base64::{engine::general_purpose::STANDARD, Engine};
use ed25519_dalek::{Signer, SigningKey};
use mosh_core::{
    device_link::roster::DeviceRoster, inbox, moss_ffi::MossNode, persistence::Persistence,
    stream_transport,
};
use serde::Serialize;
use serde_json::{json, Value};

const CHANNEL: &str = "mosh-dm-devices-v1";

#[derive(Serialize)]
enum Request {
    HistoryRequest(HistoryRequest),
    RecoveryProbe {
        session_id: String,
        request_id: String,
        round: u64,
    },
    RecoveryPull {
        round: u64,
        epoch: u64,
        request: HistoryRequest,
    },
}

#[derive(Serialize)]
struct HistoryRequest {
    session_id: String,
    request_id: String,
    offset: usize,
    body_offset: usize,
}

pub fn command(
    store: &Persistence,
    node: &MossNode,
    action: &str,
    arg: &str,
    command: &Value,
) -> Value {
    match action {
        "protocol_capture" => capture(store, arg, command),
        "protocol_send" => {
            let packet = hex::decode(command["packet"].as_str().unwrap()).unwrap();
            let frame = serde_json::to_vec(
                &json!({"channel":CHANNEL,"payload_b64":STANDARD.encode(packet)}),
            )
            .unwrap();
            node.open_stream(arg, stream_transport::ATTACHMENT_STREAM_ID)
                .unwrap();
            node.send_stream(arg, stream_transport::ATTACHMENT_STREAM_ID, &frame)
                .unwrap();
            json!({})
        }
        "protocol_read" => read_responses(command["request_id"].as_str().unwrap()),
        _ => panic!("unknown protocol command"),
    }
}

fn capture(store: &Persistence, session: &str, command: &Value) -> Value {
    let identity: Value =
        serde_json::from_slice(&store.get_device_link().unwrap().unwrap()).unwrap();
    let roster: DeviceRoster =
        serde_json::from_value(command.get("roster").unwrap_or(&identity["roster"]).clone())
            .unwrap();
    let seed: [u8; 32] = serde_json::from_value(identity["seed"].clone()).unwrap();
    let request_id = if command["kind"] == "history" && command.get("roster").is_none() {
        let session = store
            .list_sessions()
            .unwrap()
            .into_iter()
            .map(|b| serde_json::from_slice::<Value>(&b).unwrap())
            .find(|r| r["session_id"] == session)
            .unwrap();
        session["membership"]["history_import"]["request_id"]
            .as_str()
            .unwrap()
            .to_owned()
    } else {
        command["request_id"].as_str().unwrap().to_owned()
    };
    let message = if command["kind"] == "history" {
        Request::HistoryRequest(HistoryRequest {
            session_id: session.into(),
            request_id: request_id.clone(),
            offset: 0,
            body_offset: 0,
        })
    } else if command["kind"] == "recovery_pull" {
        Request::RecoveryPull {
            round: 47,
            epoch: command["epoch"].as_u64().unwrap(),
            request: HistoryRequest {
                session_id: session.into(),
                request_id: request_id.clone(),
                offset: 0,
                body_offset: 0,
            },
        }
    } else {
        Request::RecoveryProbe {
            session_id: session.into(),
            request_id: request_id.clone(),
            round: 47,
        }
    };
    let sender = identity["device"]["device_id"].as_str().unwrap();
    let recipient = command["recipient"].as_str().unwrap();
    let mut bytes = b"mosh-dm-admission-v1\0".to_vec();
    bytes.extend(serde_json::to_vec(&(&roster, sender, recipient, &message)).unwrap());
    let signature = hex::encode(SigningKey::from_bytes(&seed).sign(&bytes).to_bytes());
    let packet = serde_json::to_vec(&json!({"roster":roster,"sender":sender,"recipient":recipient,"message":message,"signature":signature})).unwrap();
    json!({"packet":hex::encode(packet),"roster":roster,"request_id":request_id})
}

fn read_responses(id: &str) -> Value {
    let mut responses = Vec::new();
    for original in inbox::drain_all() {
        let message = stream_transport::passthrough_or_deframe(original.clone());
        let packet = serde_json::from_slice::<Value>(&message.payload).ok();
        let response = packet.as_ref().map(|p| &p["message"]);
        let matching = message.channel == CHANNEL
            && response.is_some_and(|r| {
                r["HistoryBatch"]["request_id"] == id
                    || r["RecoveryOffer"]["probe"]["request_id"] == id
                    || r["RecoveryBatch"]["batch"]["request_id"] == id
                    || r["RecoveryEpoch"]["request_id"] == id
                    || r["RecoveryRemoval"]["request_id"] == id
            });
        if matching {
            responses.push(packet.unwrap());
        } else {
            inbox::deliver(original);
        }
    }
    json!(responses)
}
