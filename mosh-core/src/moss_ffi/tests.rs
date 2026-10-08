use super::*;

unsafe extern "C" fn no_public_key(_handle: MossHandle) -> *mut u8 {
    std::ptr::null_mut()
}

unsafe extern "C" fn ignore_keystore(
    _load: Option<KeyStoreLoadCallback>,
    _save: Option<KeyStoreSaveCallback>,
) -> i32 {
    MOSS_OK
}

#[test]
fn initialization_rejects_an_unverifiable_or_uncaptured_identity() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _restore = replace_test_keystore(None);
    let mut missing_public = MossFfiRuntime::load_default().unwrap();
    missing_public.get_public_key = no_public_key;
    assert!(Arc::new(missing_public)
        .init_node("missing-public", &node_config(0, None))
        .is_err());
    let mut missing_signer = MossFfiRuntime::load_default().unwrap();
    missing_signer.uninstall_keystore().unwrap();
    missing_signer.set_key_store = ignore_keystore;
    assert!(Arc::new(missing_signer)
        .init_node("missing-signer", &node_config(0, None))
        .is_err());
    let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
    assert!(runtime.init_node("verified", &node_config(0, None)).is_ok());
}

struct MemStore(Mutex<Option<Vec<u8>>>);

impl MossKeyStore for MemStore {
    fn load_identity(&self) -> Option<Vec<u8>> {
        self.0.lock().unwrap().clone()
    }
    fn save_identity(&self, bytes: &[u8]) {
        *self.0.lock().unwrap() = Some(bytes.to_vec());
    }
}

struct RestoreDebugRecordDir(Option<std::ffi::OsString>);

#[test]
fn node_signers_are_the_actual_generated_or_loaded_moss_identity() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _restore = replace_test_keystore(None);
    let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
    let first = runtime.init_node("first", &node_config(0, None)).unwrap();
    let second = runtime.init_node("second", &node_config(0, None)).unwrap();
    assert_ne!(first.public_key_hex(), second.public_key_hex());
    for node in [&first, &second] {
        assert_eq!(
            node.public_key_hex().unwrap(),
            hex::encode(node.identity_signer().unwrap().verifying_key().to_bytes())
        );
    }
    set_moss_keystore(Arc::new(MemStore(Mutex::new(None))));
    let saved = runtime.init_node("saved", &node_config(0, None)).unwrap();
    let loaded = runtime.init_node("loaded", &node_config(0, None)).unwrap();
    assert_eq!(saved.public_key_hex(), loaded.public_key_hex());
    assert_eq!(
        loaded.public_key_hex().unwrap(),
        hex::encode(loaded.identity_signer().unwrap().verifying_key().to_bytes())
    );
}

impl Drop for RestoreDebugRecordDir {
    fn drop(&mut self) {
        match self.0.take() {
            Some(value) => std::env::set_var("MOSH_DEBUG_RECORD_DIR", value),
            None => std::env::remove_var("MOSH_DEBUG_RECORD_DIR"),
        }
    }
}

#[test]
fn keystore_callbacks_round_trip_identity() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _restore = replace_test_keystore(None);
    set_moss_keystore(Arc::new(MemStore(Mutex::new(None))));

    // Nothing stored yet: probe returns 0.
    assert_eq!(unsafe { keystore_load(std::ptr::null_mut(), 0) }, 0);

    let identity = [7u8; 40];
    unsafe { keystore_save(identity.as_ptr(), identity.len() as u32) };

    // Probe reports the stored size.
    let size = unsafe { keystore_load(std::ptr::null_mut(), 0) };
    assert_eq!(size, identity.len() as u32);

    // Real read copies the bytes into the buffer.
    let mut buffer = vec![0u8; size as usize];
    let read = unsafe { keystore_load(buffer.as_mut_ptr(), buffer.len() as u32) };
    assert_eq!(read, identity.len() as u32);
    assert_eq!(buffer, identity);
}

#[test]
fn global_test_overrides_restore_nonempty_prior_state_on_unwind() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _restore_store = replace_test_keystore(None);
    let _restore_env = RestoreDebugRecordDir(std::env::var_os("MOSH_DEBUG_RECORD_DIR"));
    set_moss_keystore(Arc::new(MemStore(Mutex::new(Some(vec![9; 40])))));
    std::env::set_var("MOSH_DEBUG_RECORD_DIR", "prior recording directory");

    let result = std::panic::catch_unwind(|| {
        let _restore_store = replace_test_keystore(None);
        let _restore_env = RestoreDebugRecordDir(std::env::var_os("MOSH_DEBUG_RECORD_DIR"));
        set_moss_keystore(Arc::new(MemStore(Mutex::new(Some(vec![7; 40])))));
        std::env::set_var("MOSH_DEBUG_RECORD_DIR", "temporary recording directory");
        std::panic::resume_unwind(Box::new("exercise cleanup during unwinding"));
    });
    assert!(result.is_err());
    assert_eq!(
        std::env::var_os("MOSH_DEBUG_RECORD_DIR"),
        Some("prior recording directory".into())
    );
    let mut buffer = [0; 40];
    assert_eq!(
        unsafe { keystore_load(buffer.as_mut_ptr(), buffer.len() as u32) },
        40
    );
    assert_eq!(buffer, [9; 40]);
}

#[test]
fn keyless_node_fault_is_scoped_to_the_requesting_thread() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    let node = Arc::new(
        moss.init_node("keyless-isolation", &node_config(0, None))
            .unwrap(),
    );
    assert!(node.public_key_hex().is_some());
    let _fault = public_key_unavailable_next_node();
    let background = node.clone();
    assert!(
        std::thread::spawn(move || background.public_key_hex())
            .join()
            .unwrap()
            .is_some(),
        "background device services cannot consume another test's keyless-node fault"
    );
    assert!(node.public_key_hex().is_none());
    assert!(node.public_key_hex().is_some());
}

const TEST_MESH: &str = "mosh-runtime-smoke";
const TEST_CHANNEL: &str = "mls-control";
const TEST_PAYLOAD: &[u8] = b"mosh-runtime-payload";

#[test]
fn directed_packets_surface_a_refused_target() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
    let node = runtime
        .init_node("directed-refusal", &node_config(0, None))
        .unwrap();
    assert!(matches!(
        node.send_to_peer("not-a-peer", b"sealed-media"),
        Err(MossFfiError::Operation {
            name: "send_to_peer",
            code: -11
        })
    ));
}

#[test]
fn directed_packet_capabilities_fail_explicitly_when_unavailable() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut runtime = MossFfiRuntime::load_default().unwrap();
    runtime.send_to_peer = None;
    runtime.set_packet_callback = None;
    let node = Arc::new(runtime)
        .init_node("missing-packets", &node_config(0, None))
        .unwrap();
    assert!(matches!(
        node.send_to_peer("peer", b"bytes"),
        Err(MossFfiError::Symbol(_))
    ));
    assert!(matches!(
        node.set_packet_callback(),
        Err(MossFfiError::Symbol(_))
    ));
}

#[test]
fn directed_packet_target_rejects_nul_before_crossing_ffi() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let runtime = Arc::new(MossFfiRuntime::load_default().unwrap());
    let node = runtime
        .init_node("invalid-packet-peer", &node_config(0, None))
        .unwrap();
    assert!(matches!(
        node.send_to_peer("peer\0suffix", b"bytes"),
        Err(MossFfiError::InvalidCString(_))
    ));
}

unsafe extern "C" fn deliver_empty_packet(
    _handle: MossHandle,
    callback: Option<PacketCallback>,
) -> i32 {
    // SAFETY: the native ABI permits a null buffer for a zero-length packet;
    // the 32-byte sender stays alive throughout this synchronous callback.
    unsafe { callback.unwrap()([0xAB; 32].as_ptr(), std::ptr::null(), 0) };
    MOSS_OK
}

#[test]
fn directed_callback_preserves_a_valid_empty_native_packet() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut runtime = MossFfiRuntime::load_default().unwrap();
    runtime.set_packet_callback = Some(deliver_empty_packet);
    let node = Arc::new(runtime)
        .init_node("empty-packet", &node_config(0, None))
        .unwrap();
    drain_received_messages();
    node.set_packet_callback().unwrap();
    let messages = drain_received_messages();
    assert_eq!(
        messages.len(),
        1,
        "a valid empty buffer is still a delivered packet"
    );
    assert!(messages[0].payload.is_empty());
}

#[cfg(target_os = "windows")]
const TEST_LIBRARY_NAME: &str = "moss.dll";
#[cfg(target_os = "macos")]
const TEST_LIBRARY_NAME: &str = "libmoss.dylib";
#[cfg(all(unix, not(target_os = "macos")))]
const TEST_LIBRARY_NAME: &str = "libmoss.so";

#[test]
#[ignore]
fn two_local_moss_peers_exchange_payload() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let library_path = build_test_moss_library();
    let runtime =
        Arc::new(MossFfiRuntime::load_from_path(&library_path).expect("Moss library should load"));

    drain_received_messages();
    let alice = runtime
        .init_node(TEST_MESH, &node_config(42030, None))
        .expect("alice node should init");
    alice.start().expect("alice should start");
    alice
        .set_message_callback()
        .expect("alice callback should register");
    alice
        .subscribe(TEST_CHANNEL)
        .expect("alice should subscribe");

    let bob = runtime
        .init_node(TEST_MESH, &node_config(42031, Some("127.0.0.1:42030")))
        .expect("bob node should init");
    bob.start().expect("bob should start");
    bob.subscribe(TEST_CHANNEL).expect("bob should subscribe");
    bob.connect("127.0.0.1:42030").expect("bob should connect");

    std::thread::sleep(Duration::from_millis(250));
    bob.publish(TEST_CHANNEL, TEST_PAYLOAD)
        .expect("bob should publish");

    let received = wait_for_payload(TEST_PAYLOAD).expect("alice should receive payload");
    assert_eq!(received.channel, TEST_CHANNEL);
}

fn node_config(port: u16, static_peer: Option<&str>) -> String {
    let peers = match static_peer {
        Some(peer) => format!("[\"{peer}\"]"),
        None => "[]".to_string(),
    };

    format!(
        r#"{{"trackers":[],"listen_port":{port},"static_peers":{peers},"gossipsub":{{"heartbeat_ms":50}},"nat":{{"upnp_enabled":false,"natpmp_enabled":false,"pcp_enabled":false}}}}"#
    )
}

#[test]
fn default_node_config_ships_no_axiom_keys() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let config = MossNodeConfig {
        listen_port: 42424,
        static_peer: None,
        bind_interface: None,
    };
    let json = node_config_json(&config);
    assert!(
        !json.contains("axiom"),
        "config must not enable Axiom: {json}"
    );
}

#[test]
fn node_config_debug_plane_is_env_gated() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _restore = RestoreDebugRecordDir(std::env::var_os("MOSH_DEBUG_RECORD_DIR"));
    let config = MossNodeConfig {
        listen_port: 42424,
        static_peer: None,
        bind_interface: None,
    };
    std::env::remove_var("MOSH_DEBUG_RECORD_DIR");
    let plain = node_config_json(&config);
    assert!(
        !plain.contains("debug"),
        "shipping config must not open the debug plane: {plain}"
    );

    let dir = std::env::temp_dir().join("mosh-debug-test");
    std::fs::create_dir_all(&dir).expect("temp dir exists");
    std::env::set_var("MOSH_DEBUG_RECORD_DIR", &dir);
    let debugged = node_config_json(&config);
    std::env::remove_var("MOSH_DEBUG_RECORD_DIR");
    assert!(
        debugged.contains(r#""debug":{"enabled":true"#),
        "env var must open the debug plane: {debugged}"
    );
    assert!(
        debugged.contains(".mossrec"),
        "debug plane must record to the requested dir: {debugged}"
    );
}

fn build_test_moss_library() -> std::path::PathBuf {
    let manifest_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output_dir = manifest_dir.join("target").join("moss-test");
    let output_path = output_dir.join(TEST_LIBRARY_NAME);
    // The Moss checkout lives at <repo>/moss, i.e. one level up from the
    // crate manifest dir (mosh-core). A previous extra `..` only resolved
    // by accident when a sibling moss/ checkout existed next to the repo.
    let moss_dir = manifest_dir.join("..").join("moss");

    std::fs::create_dir_all(&output_dir).expect("Moss test output dir should exist");
    let output = std::process::Command::new("go")
        .arg("build")
        .arg("-buildmode=c-shared")
        .arg("-o")
        .arg(&output_path)
        .arg("./cmd/moss-ffi")
        .current_dir(&moss_dir)
        .output()
        .expect("go build should start");

    if !output.status.success() {
        panic!(
            "Moss shared build failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    output_path
}
