mod api;
pub(crate) mod crypto;
mod dm;
mod protocol;
pub(crate) mod stdio;
use std::cell::Cell;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};

use mosh_core::attachment_store::AttachmentStore;
use mosh_core::device_link::DeviceLinkRuntime;
use mosh_core::moss_ffi::{set_moss_keystore, MossFfiRuntime};
use mosh_core::persistence::Persistence;
use mosh_core::private_dm_runtime::PrivateDmRuntime;
use mosh_core::shared_node::SharedMossNode;
use serde_json::{json, Value};

const OUTPUT_PREFIX: &str = "MOSH_TEST_JSON ";
static NETWORK_SCENARIO: Mutex<()> = Mutex::new(());
thread_local! {
    static NETWORK_SCOPE: Cell<u64> = const { Cell::new(0) };
}

/// Serialize LAN probes and give local-tracker scenarios independent networks.
pub fn isolated_network_scenario() -> std::sync::MutexGuard<'static, ()> {
    let guard = NETWORK_SCENARIO
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    NETWORK_SCOPE.with(|scope| scope.set(rand::random()));
    guard
}

pub struct Peer {
    child: Child,
    stdin: ChildStdin,
    replies: mpsc::Receiver<Value>,
    dir: PathBuf,
    api: bool,
    manual_dm: bool,
    network_scope: u64,
    worker: &'static str,
    pub port: u16,
}

impl Peer {
    pub fn new() -> Self {
        Self::new_installation(false, false, "independent_installation_process")
    }

    pub fn new_api() -> Self {
        Self::new_installation(true, false, "independent_installation_process")
    }

    #[allow(
        dead_code,
        reason = "Shared harness scheduling mode used by the DM admission tests."
    )]
    pub fn new_manual_dm() -> Self {
        Self::new_installation(false, true, "independent_installation_process")
    }

    #[allow(
        dead_code,
        reason = "Used by the core's independent legacy migration workers."
    )]
    pub fn new_with_worker(worker: &'static str) -> Self {
        Self::new_installation(false, false, worker)
    }

    fn new_installation(api: bool, manual_dm: bool, worker: &'static str) -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-link-flow-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("storage-key.bin"), rand::random::<[u8; 32]>()).unwrap();
        Self::start(dir, api, manual_dm, NETWORK_SCOPE.with(Cell::get), worker)
    }

    fn start(
        dir: PathBuf,
        api: bool,
        manual_dm: bool,
        network_scope: u64,
        worker: &'static str,
    ) -> Self {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", worker, "--ignored", "--nocapture"])
            .env("MOSH_LINK_TEST_DIR", &dir)
            .env("MOSH_LINK_TEST_PORT", "0")
            .env("MOSH_LINK_TEST_API", if api { "1" } else { "0" })
            .env("MOSH_DM_MANUAL_SERVICE", if manual_dm { "1" } else { "0" })
            .env("MOSH_TEST_NETWORK_SCOPE", network_scope.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap();
        let stdin = child.stdin.take().unwrap();
        let stdout = child.stdout.take().unwrap();
        let replies = read_replies(stdout);
        let mut peer = Self {
            child,
            stdin,
            replies,
            dir,
            api,
            manual_dm,
            network_scope,
            worker,
            port: 0,
        };
        peer.ask(json!({"action":"snapshot"}));
        if !api {
            peer.port = peer.ask(json!({"action":"network"}))["listen_port"]
                .as_u64()
                .unwrap()
                .try_into()
                .unwrap();
        }
        peer
    }

    pub fn ask(&mut self, command: Value) -> Value {
        writeln!(self.stdin, "{command}").unwrap();
        self.stdin.flush().unwrap();
        self.replies
            .recv_timeout(Duration::from_secs(30))
            .unwrap_or_else(|error| {
                let deadline = Instant::now() + Duration::from_millis(250);
                let status = loop {
                    let status = self.child.try_wait();
                    if !matches!(status, Ok(None)) || Instant::now() >= deadline {
                        break status;
                    }
                    std::thread::sleep(Duration::from_millis(10));
                };
                panic!(
                    "peer action {} failed: {error}; process status: {:?}",
                    command["action"], status
                )
            })
    }

    pub fn connect(&mut self, other: &Self) {
        // Public bridge scenarios deliberately rely on automatic discovery.
        if self.api {
            return;
        }
        self.ask(json!({"action":"connect","argument":format!("127.0.0.1:{}", other.port)}));
    }

    pub fn wait_phase(&mut self, phase: &str) -> Value {
        let deadline = Instant::now() + Duration::from_secs(if self.api { 60 } else { 30 });
        loop {
            let snapshot = self.ask(json!({"action":"snapshot"}));
            if snapshot["phase"] == phase {
                return snapshot;
            }
            assert!(
                Instant::now() < deadline,
                "expected {phase}, got phase={}, error={}",
                snapshot["phase"],
                snapshot["error"]
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    pub fn restart(&mut self) {
        self.stop();
        let mut replacement = Self::start(
            self.dir.clone(),
            self.api,
            self.manual_dm,
            self.network_scope,
            self.worker,
        );
        std::mem::swap(self, &mut replacement);
        // Keep this installation's persistent state; only the killed process is old.
        replacement.dir = PathBuf::new();
    }

    pub fn stop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = writeln!(self.stdin, "{}", json!({"action":"shutdown"}));
            let _ = self.stdin.flush();
            let status = self.child.wait().unwrap();
            if !status.success() {
                eprintln!("peer exited unsuccessfully: {status}");
            }
        }
    }

    #[allow(dead_code)] // Shared helper also compiles in the DM test executable.
    pub fn crash(&mut self) {
        self.child.kill().unwrap();
        self.child.wait().unwrap();
    }
}

fn read_replies(stdout: ChildStdout) -> mpsc::Receiver<Value> {
    let (send, replies) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            let line = match line {
                Ok(line) => line,
                Err(error) => {
                    eprintln!("peer stdout read failed: {error:?}");
                    break;
                }
            };
            if let Some(json) = line.strip_prefix(OUTPUT_PREFIX) {
                if send.send(serde_json::from_str(json).unwrap()).is_err() {
                    break;
                }
            } else if !line.is_empty() {
                eprintln!("peer: {line}");
            }
        }
    });
    replies
}

impl Drop for Peer {
    fn drop(&mut self) {
        self.stop();
        if !self.dir.as_os_str().is_empty() {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }
}

pub fn peer_process() {
    peer_process_with(|_, _, _| None);
}

pub fn peer_process_with(extra: fn(&Persistence, &str, &Value) -> Option<Value>) {
    stdio::isolate_from_moss();
    let dir = PathBuf::from(std::env::var("MOSH_LINK_TEST_DIR").unwrap());
    if std::env::var("MOSH_LINK_TEST_API").as_deref() == Ok("1") {
        return api::run(dir);
    }
    mosh_core::api::private_dm::set_app_data_dir(dir.to_string_lossy().into_owned()).unwrap();
    let port = std::env::var("MOSH_LINK_TEST_PORT")
        .unwrap()
        .parse()
        .unwrap();
    let key = std::fs::read(dir.join("storage-key.bin"))
        .unwrap()
        .try_into()
        .unwrap();
    let store = Arc::new(Persistence::open_with_dek(&dir.join("history.redb"), key).unwrap());
    set_moss_keystore(store.clone());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    moss.install_keystore().unwrap();
    let shared = SharedMossNode::new(moss);
    let node = shared.acquire(port, None).unwrap();
    let runtime = Arc::new(Mutex::new(
        DeviceLinkRuntime::open(shared.clone(), store.clone()).unwrap(),
    ));
    let dm = dm_runtime(shared, store.clone(), dir);
    let service = runtime.clone();
    std::thread::spawn(move || loop {
        let _ = service.lock().unwrap().service();
        std::thread::sleep(Duration::from_millis(100));
    });
    serve(runtime, node, dm, store, extra);
}

fn dm_runtime(
    shared: Arc<SharedMossNode>,
    store: Arc<Persistence>,
    dir: PathBuf,
) -> Arc<Mutex<PrivateDmRuntime>> {
    let attachments = Arc::new(AttachmentStore::new(dir.clone()).unwrap());
    let mut dm = PrivateDmRuntime::from_shared_node(shared, attachments, Some(store));
    dm.rehydrate();
    let dm = Arc::new(Mutex::new(dm));
    let dm_service = dm.clone();
    if std::env::var("MOSH_DM_MANUAL_SERVICE").as_deref() != Ok("1") {
        std::thread::spawn(move || loop {
            dm_service.lock().unwrap().service();
            std::thread::sleep(Duration::from_millis(100));
        });
    }
    dm
}

fn serve(
    runtime: Arc<Mutex<DeviceLinkRuntime>>,
    node: Arc<mosh_core::moss_ffi::MossNode>,
    dm: Arc<Mutex<PrivateDmRuntime>>,
    store: Arc<Persistence>,
    extra: fn(&Persistence, &str, &Value) -> Option<Value>,
) {
    for line in std::io::stdin().lock().lines() {
        let command: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let action = command["action"].as_str().unwrap();
        if action == "shutdown" {
            break;
        }
        let arg = command["argument"].as_str().unwrap_or_default().to_string();
        if let Some(response) = extra(&store, action, &command) {
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        if action.starts_with("protocol_") {
            let response = protocol::command(&store, &node, action, &arg, &command);
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        if action.starts_with("crypto_") {
            // Each worker inspects only its own encrypted MLS state. The parent
            // receives ciphertext and public metadata, never a private snapshot.
            let response = crypto::command(&store, action, &arg, &command);
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        if action.starts_with("dm_") {
            let response = dm::command(&mut dm.lock().unwrap(), action, &arg, &command);
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        let mut rt = runtime.lock().unwrap();
        if matches!(action, "names" | "name_set" | "name_reset") {
            let result = match action {
                "name_set" => rt.rename_chat(&arg, command["name"].as_str().unwrap()),
                "name_reset" => rt.reset_chat_name(&arg),
                _ => rt.chat_names_snapshot(),
            };
            let response = match result {
                Ok(snapshot) => serde_json::to_value(snapshot).unwrap(),
                Err(error) => json!({"error":format!("{:?}", error.kind)}),
            };
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        let result = match action {
            "connect" => {
                node.connect(&arg).unwrap();
                rt.snapshot()
            }
            "snapshot" => rt.snapshot(),
            "network" => {
                println!("{OUTPUT_PREFIX}{}", node.mesh_info_json().unwrap());
                std::io::stdout().flush().unwrap();
                continue;
            }
            "qr" => rt.begin_link(),
            "import" => rt.join_link(arg, command["name"].as_str().unwrap_or_default().into()),
            "approve" => rt.approve(arg),
            "cancel" => rt.cancel(),
            "revoke" => rt.revoke(arg),
            _ => panic!("unknown command"),
        };
        let response = match result {
            Ok(s) => serde_json::to_value(s).unwrap(),
            Err(e) => json!({"error":e.kind}),
        };
        println!("{OUTPUT_PREFIX}{response}");
        std::io::stdout().flush().unwrap();
    }
}
