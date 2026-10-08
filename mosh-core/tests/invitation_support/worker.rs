//! Reuse process/stdout and encrypted MLS probes; only invitation commands differ.
use crate::link_support::{crypto, stdio};

use mosh_core::attachment_store::AttachmentStore;
use mosh_core::diagnostics_log;
use mosh_core::moss_ffi::{set_moss_keystore, MossFfiRuntime, MossNode};
use mosh_core::persistence::Persistence;
use mosh_core::private_dm_runtime::{AcceptInviteRequest, PrivateDmRuntime, StartSessionRequest};
use mosh_core::shared_node::SharedMossNode;
use serde::Serialize;
use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub fn run() {
    stdio::isolate_from_moss();
    let dir = PathBuf::from(std::env::var("MOSH_LINK_TEST_DIR").unwrap());
    mosh_core::api::private_dm::set_app_data_dir(dir.to_string_lossy().into_owned()).unwrap();
    let key = std::fs::read(dir.join("storage-key.bin"))
        .unwrap()
        .try_into()
        .unwrap();
    let store = Arc::new(Persistence::open_with_dek(&dir.join("history.redb"), key).unwrap());
    set_moss_keystore(store.clone());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    moss.install_keystore().unwrap();
    let shared = SharedMossNode::new(moss);
    let node = shared.acquire(0, None).unwrap();
    let attachments = Arc::new(AttachmentStore::new(dir).unwrap());
    let mut runtime = PrivateDmRuntime::from_shared_node(shared, attachments, Some(store.clone()));
    runtime.rehydrate();
    let runtime = Arc::new(Mutex::new(runtime));
    let service = runtime.clone();
    std::thread::spawn(move || loop {
        service.lock().unwrap().service();
        std::thread::sleep(Duration::from_millis(100));
    });
    serve(runtime, node, store);
}

fn serve(runtime: Arc<Mutex<PrivateDmRuntime>>, node: Arc<MossNode>, store: Arc<Persistence>) {
    for line in std::io::stdin().lock().lines() {
        let request: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let action = request["action"].as_str().unwrap();
        if action == "shutdown" {
            break;
        }
        let reply = command(
            &mut runtime.lock().unwrap(),
            &node,
            &store,
            action,
            &request,
        );
        println!("MOSH_TEST_JSON {reply}");
        std::io::stdout().flush().unwrap();
    }
}

fn command(
    dm: &mut PrivateDmRuntime,
    node: &MossNode,
    store: &Persistence,
    action: &str,
    request: &Value,
) -> Value {
    let id = request["argument"].as_str().unwrap_or_default();
    match action {
        "snapshot" | "dm_list" => result(dm.list_sessions()),
        "network" => serde_json::from_str(&node.mesh_info_json().unwrap()).unwrap(),
        "create" => result(dm.create_pending_invite(StartSessionRequest {
            display_name: "Creator".into(),
            listen_port: 0,
            static_peer: None,
        })),
        "pending" => result(dm.list_pending_invites()),
        "replace" => result(dm.replace_invite(id)),
        "open" => result(dm.open_session(id)),
        "dm_poll" => result(dm.poll_session(id)),
        "dm_accept" => result(dm.accept_invite(AcceptInviteRequest {
            invite_uri: id.into(),
            display_name: request["name"].as_str().unwrap().into(),
            listen_port: 0,
            static_peer: None,
        })),
        "dm_send" => result(dm.send_message(id, request["body"].as_str().unwrap().into())),
        "evidence" => {
            dm.service();
            let mut status = crypto::command(store, "crypto_status", id, request);
            let reason = request["reason"].as_str().unwrap();
            status["rejections"] = json!(rejections(id, reason));
            status
        }
        _ => panic!("unknown invitation command"),
    }
}

fn result<T: Serialize, E: std::fmt::Display>(result: Result<T, E>) -> Value {
    match result {
        Ok(value) => serde_json::to_value(value).unwrap(),
        Err(error) => json!({"error":error.to_string()}),
    }
}

// Read existing rejection evidence without returning tokens or log text.
fn rejections(id: &str, reason: &str) -> usize {
    let Some(path) = diagnostics_log::current_log_path() else {
        return 0;
    };
    let log = std::fs::read_to_string(path).unwrap();
    let marker = format!(" frame {id} dropping inbound frame: invalid invite: {reason}");
    log.lines().filter(|line| line.contains(&marker)).count()
}
