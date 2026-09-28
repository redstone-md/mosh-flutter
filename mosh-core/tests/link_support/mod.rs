mod api;
mod dm;
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

pub struct Peer {
    child: Child,
    stdin: ChildStdin,
    replies: mpsc::Receiver<Value>,
    dir: PathBuf,
    api: bool,
    pub port: u16,
}

impl Peer {
    pub fn new() -> Self {
        Self::new_installation(false)
    }

    pub fn new_api() -> Self {
        Self::new_installation(true)
    }

    fn new_installation(api: bool) -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-link-flow-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&dir).unwrap();
        Self::start(dir, api)
    }

    fn start(dir: PathBuf, api: bool) -> Self {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "independent_installation_process",
                "--ignored",
                "--nocapture",
            ])
            .env("MOSH_LINK_TEST_DIR", &dir)
            .env("MOSH_LINK_TEST_PORT", "0")
            .env("MOSH_LINK_TEST_API", if api { "1" } else { "0" })
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
            .expect("real peer must answer")
    }

    pub fn connect(&mut self, other: &Self) {
        self.ask(json!({"action":"connect","argument":format!("127.0.0.1:{}", other.port)}));
    }

    pub fn wait_phase(&mut self, phase: &str) -> Value {
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            let snapshot = self.ask(json!({"action":"snapshot"}));
            if snapshot["phase"] == phase {
                return snapshot;
            }
            assert!(
                Instant::now() < deadline,
                "expected {phase}, got {snapshot}"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    pub fn restart(&mut self) {
        self.stop();
        let mut replacement = Self::start(self.dir.clone(), self.api);
        std::mem::swap(self, &mut replacement);
        // Keep this installation's persistent state; only the killed process is old.
        replacement.dir = PathBuf::new();
    }

    pub fn stop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = writeln!(self.stdin, "{}", json!({"action":"shutdown"}));
            let _ = self.stdin.flush();
            self.child.wait().unwrap();
        }
    }
}

fn read_replies(stdout: ChildStdout) -> mpsc::Receiver<Value> {
    let (send, replies) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout)
            .lines()
            .map_while(std::result::Result::ok)
        {
            if let Some(json) = line.strip_prefix(OUTPUT_PREFIX) {
                if send.send(serde_json::from_str(json).unwrap()).is_err() {
                    break;
                }
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
    let dir = PathBuf::from(std::env::var("MOSH_LINK_TEST_DIR").unwrap());
    if std::env::var("MOSH_LINK_TEST_API").as_deref() == Ok("1") {
        return api::run(dir);
    }
    let port = std::env::var("MOSH_LINK_TEST_PORT")
        .unwrap()
        .parse()
        .unwrap();
    let store = Arc::new(Persistence::open_with_dek(&dir.join("history.redb"), [91; 32]).unwrap());
    set_moss_keystore(store.clone());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    moss.install_keystore().unwrap();
    let shared = SharedMossNode::new(moss);
    let node = shared.acquire(port, None).unwrap();
    let runtime = Arc::new(Mutex::new(
        DeviceLinkRuntime::open(shared.clone(), store.clone()).unwrap(),
    ));
    let dm = dm_runtime(shared, store, dir);
    let service = runtime.clone();
    std::thread::spawn(move || loop {
        let _ = service.lock().unwrap().service();
        std::thread::sleep(Duration::from_millis(100));
    });
    serve(runtime, node, dm);
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
    std::thread::spawn(move || loop {
        dm_service.lock().unwrap().service();
        std::thread::sleep(Duration::from_millis(100));
    });
    dm
}

fn serve(
    runtime: Arc<Mutex<DeviceLinkRuntime>>,
    node: Arc<mosh_core::moss_ffi::MossNode>,
    dm: Arc<Mutex<PrivateDmRuntime>>,
) {
    for line in std::io::stdin().lock().lines() {
        let command: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let action = command["action"].as_str().unwrap();
        if action == "shutdown" {
            break;
        }
        let arg = command["argument"].as_str().unwrap_or_default().to_string();
        if action.starts_with("dm_") {
            let response = dm::command(&mut dm.lock().unwrap(), action, &arg, &command);
            println!("{OUTPUT_PREFIX}{response}");
            std::io::stdout().flush().unwrap();
            continue;
        }
        let mut rt = runtime.lock().unwrap();
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
            "qr" => rt.create_qr(arg),
            "import" => rt.import_qr(arg),
            "approve" => rt.approve(arg),
            "cancel" => rt.cancel(),
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
