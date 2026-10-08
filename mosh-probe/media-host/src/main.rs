mod engine;
mod transport;
// Reuse the tested Windows pipe isolation before Go adopts inherited stdio.
#[path = "../../../mosh-core/tests/link_support/stdio.rs"]
mod stdio;

use engine::Engine;
use mosh_core::moss_ffi::{
    MossFfiRuntime, MossNode, PACKET_INBOX_CHANNEL_PREFIX, drain_received_messages,
};
use serde_json::{Value, json};
use std::io::{BufRead, Write};
use std::sync::{
    Arc,
    mpsc::{Receiver, sync_channel},
};
use std::time::{Duration, Instant};
use transport::Transport;

type ProbeResult<T = ()> = Result<T, Box<dyn std::error::Error>>;

fn emit(value: Value) -> ProbeResult {
    println!("MOSH_MEDIA_JSON {value}");
    std::io::stdout().flush()?;
    Ok(())
}

fn commands() -> Receiver<Value> {
    let (send, receive) = sync_channel(8);
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            let Ok(value) = serde_json::from_str(&line) else {
                break;
            };
            if send.send(value).is_err() {
                break;
            }
        }
    });
    receive
}

fn node(mesh: &str) -> ProbeResult<Arc<MossNode>> {
    let runtime = Arc::new(MossFfiRuntime::load_default()?);
    let config = json!({"trackers":[], "listen_port":0,
        "nat":{"upnp_enabled":false,"natpmp_enabled":false,"pcp_enabled":false}});
    let node = Arc::new(runtime.init_node(mesh, &config.to_string())?);
    node.set_packet_callback()?;
    node.start()?;
    Ok(node)
}

fn incoming(peer: &str) -> Value {
    let channel = format!("{PACKET_INBOX_CHANNEL_PREFIX}{peer}");
    let (mut packets, mut candidates) = (Vec::new(), Vec::new());
    for message in drain_received_messages() {
        if message.channel != channel || message.payload.len() > 2007 {
            continue;
        }
        if message.payload.starts_with(transport::MAGIC) {
            packets.push(message.payload);
        } else if message.payload.starts_with(b"MI1")
            && let Ok(candidate) = std::str::from_utf8(&message.payload[3..])
        {
            candidates.push(candidate.to_owned());
        }
    }
    json!({"action":"tick", "packets":packets, "candidates":candidates})
}

fn pump(
    node: &MossNode,
    peer: &str,
    engine: &Engine,
    transport: &Transport,
    commands: &Receiver<Value>,
) -> ProbeResult {
    let enqueue = transport.sender();
    let deadline = Instant::now() + Duration::from_secs(3700);
    while Instant::now() < deadline {
        for value in commands.try_iter() {
            if value["action"] == "stop" {
                return Ok(());
            }
            let mut reply = engine.ask(value.clone())?;
            if value["action"] == "snapshot" {
                reply["transport"] = transport.snapshot();
            }
            emit(reply)?;
        }
        let outgoing = engine.ask(incoming(peer))?;
        for packet in outgoing["packets"].as_array().ok_or("missing packets")? {
            enqueue(serde_json::from_value(packet.clone())?);
        }
        for candidate in outgoing["candidates"]
            .as_array()
            .ok_or("missing candidates")?
        {
            let candidate = candidate.as_str().ok_or("invalid candidate")?;
            node.send_to_peer(peer, &[b"MI1".as_slice(), candidate.as_bytes()].concat())?;
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    Err("probe lifetime exceeded".into())
}

fn main() -> ProbeResult {
    stdio::isolate_from_moss();
    let role = std::env::args().nth(1).ok_or("expected caller or callee")?;
    if role == "factory" {
        return factory_check();
    }
    if !["caller", "callee"].contains(&role.as_str()) {
        return Err("invalid role".into());
    }
    let node = node(&std::env::var("MOSH_MEDIA_MESH")?)?;
    let info: Value = serde_json::from_str(&node.mesh_info_json().ok_or("missing Moss info")?)?;
    emit(json!({"peer": node.public_key_hex(), "port": info["listen_port"]}))?;
    let commands = commands();
    let connect = commands.recv_timeout(Duration::from_secs(60))?;
    node.connect(connect["address"].as_str().ok_or("missing address")?)?;
    let peer = connect["peer"].as_str().ok_or("missing peer")?;
    let transport = Transport::new(node.clone(), peer.into());
    let engine = Engine::new(&role)?;
    emit(json!({"ok":true}))?;
    pump(&node, peer, &engine, &transport, &commands)
}

/// Exercise native factory/offer/socket creation without loading Moss.
fn factory_check() -> ProbeResult {
    let engine = Engine::new("caller")?;
    // The returned private test keys stay in this process and are never printed.
    engine.ask(json!({"action":"offer"}))?;
    for _ in 0..60 {
        engine.ask(json!({"action":"tick"}))?;
        std::thread::sleep(Duration::from_millis(33));
    }
    emit(json!({"factory_check":"pass", "moss_loaded":false}))
}
