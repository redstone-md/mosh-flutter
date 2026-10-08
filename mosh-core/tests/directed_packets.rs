//! Real-process checks: Moss's keystore is global within each installation.
use mosh_core::moss_ffi::{
    drain_received_messages, MossFfiRuntime, PACKET_INBOX_CHANNEL_PREFIX,
    STREAM_INBOX_CHANNEL_PREFIX,
};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

const PREFIX: &str = "MOSH_PACKET_TEST ";

struct Peer {
    child: Child,
    input: ChildStdin,
    replies: mpsc::Receiver<Value>,
    key: String,
    port: u16,
}

impl Peer {
    fn new(mesh: &str, packets_first: bool) -> Self {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "packet_worker", "--ignored", "--nocapture"])
            .env("MOSH_PACKET_TEST_MESH", mesh)
            .env(
                "MOSH_PACKET_TEST_ORDER",
                if packets_first { "packets" } else { "streams" },
            )
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap();
        let input = child.stdin.take().unwrap();
        let output = child.stdout.take().unwrap();
        let (send, replies) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(output).lines().map_while(Result::ok) {
                if let Some(value) = line.strip_prefix(PREFIX) {
                    if send.send(serde_json::from_str(value).unwrap()).is_err() {
                        break;
                    }
                }
            }
        });
        let ready = replies.recv_timeout(Duration::from_secs(30)).unwrap();
        Self {
            child,
            input,
            replies,
            key: ready["key"].as_str().unwrap().into(),
            port: ready["port"].as_u64().unwrap() as u16,
        }
    }

    fn ask(&mut self, value: Value) -> Value {
        writeln!(self.input, "{value}").unwrap();
        self.input.flush().unwrap();
        self.replies
            .recv_timeout(Duration::from_secs(30))
            .expect("real Moss peer must reply")
    }

    fn receive(&mut self, expected: &[u8]) -> String {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let frames = self.ask(json!({"action":"drain"}));
            for frame in frames.as_array().unwrap() {
                if frame["payload"] == json!(expected) {
                    return frame["channel"].as_str().unwrap().into();
                }
            }
            assert!(
                Instant::now() < deadline,
                "payload {expected:?} did not arrive; last batch: {frames}"
            );
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

impl Drop for Peer {
    fn drop(&mut self) {
        let _ = writeln!(self.input, "{}", json!({"action":"stop"}));
        let _ = self.input.flush();
        let deadline = Instant::now() + Duration::from_secs(2);
        while self.child.try_wait().ok().flatten().is_none() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

#[test]
fn directed_payload_and_stream_callbacks_coexist_in_both_registration_orders() {
    let mesh = format!("packet-test-{}", rand::random::<u64>());
    let (mut left, mut right) = (Peer::new(&mesh, true), Peer::new(&mesh, false));
    assert_ne!(
        left.key, right.key,
        "independent processes have independent identities"
    );
    assert_eq!(
        left.ask(json!({"action":"connect", "address":format!("127.0.0.1:{}", right.port)})),
        json!({"ok":true})
    );
    exchange(&mut left, &mut right);
    exchange(&mut right, &mut left);
}

fn exchange(sender: &mut Peer, receiver: &mut Peer) {
    assert_eq!(
        sender.ask(json!({"action":"packet", "peer":receiver.key})),
        json!({"ok":true})
    );
    assert_eq!(
        receiver.receive(b"packet-fixture"),
        format!("{PACKET_INBOX_CHANNEL_PREFIX}{}", sender.key)
    );
    assert_eq!(
        sender.ask(json!({"action":"empty", "peer":receiver.key})),
        json!({"ok":true})
    );
    assert_eq!(
        receiver.receive(b""),
        format!("{PACKET_INBOX_CHANNEL_PREFIX}{}", sender.key)
    );
    assert_eq!(
        receiver.ask(json!({"action":"open", "peer":sender.key})),
        json!({"ok":true})
    );
    assert_eq!(
        sender.ask(json!({"action":"stream", "peer":receiver.key})),
        json!({"ok":true})
    );
    assert_eq!(
        receiver.receive(b"stream-fixture"),
        format!("{STREAM_INBOX_CHANNEL_PREFIX}{}", sender.key)
    );
}

#[test]
#[ignore = "Launched as an independent Moss installation by the parent test."]
fn packet_worker() {
    let mesh = std::env::var("MOSH_PACKET_TEST_MESH").unwrap();
    let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
    let config = json!({"listen_port":0,"trackers":[],"dht_enabled":false,"lan_discovery_enabled":false,"nat":{"upnp_enabled":false,"natpmp_enabled":false,"pcp_enabled":false}});
    let node = runtime.init_node(&mesh, &config.to_string()).unwrap();
    if std::env::var("MOSH_PACKET_TEST_ORDER").unwrap() == "packets" {
        node.set_packet_callback().unwrap();
        node.register_stream_handler(17).unwrap();
    } else {
        node.register_stream_handler(17).unwrap();
        node.set_packet_callback().unwrap();
    }
    node.start().unwrap();
    let info: Value = serde_json::from_str(&node.mesh_info_json().unwrap()).unwrap();
    println!(
        "{PREFIX}{}",
        json!({"key":node.public_key_hex(), "port":info["listen_port"]})
    );
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let value: Value = serde_json::from_str(&line).unwrap();
        if value["action"] == "stop" {
            break;
        }
        let response = match value["action"].as_str().unwrap() {
            "connect" => node
                .connect(value["address"].as_str().unwrap())
                .map(|_| json!({"ok":true})),
            "packet" => node
                .send_to_peer(value["peer"].as_str().unwrap(), b"packet-fixture")
                .map(|_| json!({"ok":true})),
            "empty" => node
                .send_to_peer(value["peer"].as_str().unwrap(), b"")
                .map(|_| json!({"ok":true})),
            "stream" => node
                .send_stream(value["peer"].as_str().unwrap(), 17, b"stream-fixture")
                .map(|_| json!({"ok":true})),
            "open" => node
                .open_stream(value["peer"].as_str().unwrap(), 17)
                .map(|_| json!({"ok":true})),
            "drain" => Ok(json!(drain_received_messages()
                .into_iter()
                .map(|message| json!({"channel":message.channel,"payload":message.payload}))
                .collect::<Vec<_>>())),
            _ => panic!("unknown fixture action"),
        }
        .unwrap_or_else(|error| json!({"error":error.to_string()}));
        println!("{PREFIX}{response}");
        std::io::stdout().flush().unwrap();
    }
}
