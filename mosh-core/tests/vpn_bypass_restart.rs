//! Saved consent and the active binding must survive independent app launches.
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use mosh_core::api::{private_dm, shared_runtime, vpn};
use mosh_core::moss_ffi::{self, MossNodeConfig};
use mosh_core::network_inventory::{self, NetworkInterfaceInfo};
use mosh_core::private_dm_runtime::StartSessionRequest;
use mosh_core::vpn_consent;

struct Installation {
    dir: PathBuf,
    network_scope: u64,
}

impl Installation {
    fn new() -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-vpn-restart-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&dir).unwrap();
        Self {
            dir,
            network_scope: rand::random(),
        }
    }

    fn launch(&self, step: &str) {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "restart_worker", "--ignored", "--nocapture"])
            .env("MOSH_VPN_TEST_DIR", &self.dir)
            .env("MOSH_VPN_TEST_STEP", step)
            .env("MOSH_TEST_NETWORK_SCOPE", self.network_scope.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(45);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                assert!(status.success(), "VPN restart step {step} failed: {status}");
                return;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                panic!("VPN restart step {step} timed out");
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn rewrite_adapter(&self, name: &str, index: Option<u32>) {
        let dir = self.dir.join("mosh");
        let mut consent = vpn_consent::load(&dir).unwrap();
        consent.interface = name.into();
        consent.index = index.unwrap_or(consent.index);
        vpn_consent::save(&dir, &consent).unwrap();
    }

    fn save_unavailable_adapter(&self) {
        vpn_consent::save(
            &self.dir.join("mosh"),
            &vpn_consent::VpnBypassConsent {
                interface: "unavailable-adapter".into(),
                index: u32::MAX,
            },
        )
        .unwrap();
    }
}

impl Drop for Installation {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

#[test]
#[ignore = "requires a connected physical IPv4 adapter; run locally with --ignored"]
fn saved_bypass_survives_process_restart() {
    let installation = Installation::new();
    installation.launch("enable");
    installation.launch("on");
    installation.launch("disable");
    installation.launch("off");
}

#[test]
#[ignore = "requires a connected physical IPv4 adapter; run locally with --ignored"]
fn a_renamed_saved_adapter_resolves_by_its_index_at_startup() {
    let installation = Installation::new();
    installation.launch("enable");
    installation.rewrite_adapter("previous-adapter-name", None);
    installation.launch("on");
}

#[test]
fn an_unavailable_saved_adapter_does_not_prevent_real_moss_startup() {
    let installation = Installation::new();
    installation.save_unavailable_adapter();
    installation.launch("unavailable");
}

#[test]
#[ignore = "requires a connected physical IPv4 adapter; run locally with --ignored"]
fn an_explicit_process_override_takes_precedence_over_saved_consent() {
    let installation = Installation::new();
    installation.launch("enable");
    installation.launch("manual");
}

#[test]
#[ignore = "worker launched by the independent-process VPN restart tests"]
fn restart_worker() {
    let dir = std::env::var("MOSH_VPN_TEST_DIR").unwrap();
    private_dm::set_app_data_dir(dir).unwrap();
    private_dm::set_history_dek(vec![7; 32]).unwrap();
    assert_eq!(
        vpn::get_bind_interface(),
        None,
        "fresh process starts unbound"
    );
    match std::env::var("MOSH_VPN_TEST_STEP").unwrap().as_str() {
        "enable" => enable_after_start(),
        "on" => assert_saved_start(),
        "disable" => disable_after_start(),
        "off" => {
            assert_eq!(vpn::get_vpn_bypass_consent(), None);
            start_real_node();
            assert_binding(None);
        }
        "unavailable" => {
            assert_eq!(
                vpn::get_vpn_bypass_consent().unwrap().interface,
                "unavailable-adapter"
            );
            start_real_node();
            assert_binding(None);
            assert!(vpn::get_vpn_bypass_consent().is_some());
        }
        "manual" => assert_manual_override(),
        step => panic!("unknown VPN restart step: {step}"),
    }
}

fn physical_adapter() -> NetworkInterfaceInfo {
    network_inventory::list_interfaces()
        .unwrap()
        .into_iter()
        .find(|iface| {
            iface.is_up
                && !iface.is_loopback
                && !iface.is_virtual
                && iface
                    .ipv4
                    .as_deref()
                    .is_some_and(|ip| !ip.is_empty() && !ip.starts_with("169.254."))
        })
        .expect("real VPN test needs a connected physical IPv4 adapter")
}

fn start_real_node() {
    private_dm::create_invite(StartSessionRequest {
        display_name: "VPN restart test".into(),
        listen_port: 0,
        static_peer: None,
    })
    .expect("public API must start a real shared Moss node");
}

fn assert_binding(expected: Option<String>) {
    assert_eq!(vpn::get_bind_interface(), expected);
    let config: serde_json::Value =
        serde_json::from_str(&moss_ffi::node_config_json(&MossNodeConfig {
            listen_port: 0,
            static_peer: None,
            bind_interface: None,
        }))
        .unwrap();
    assert_eq!(config["bind_interface"].as_str(), expected.as_deref());
}

fn enable_after_start() {
    assert_eq!(vpn::get_vpn_bypass_consent(), None);
    start_real_node();
    let iface = physical_adapter();
    vpn::set_vpn_bypass_consent(Some(iface.name.clone())).unwrap();
    assert_eq!(vpn::get_vpn_bypass_consent().unwrap().interface, iface.name);
    assert_binding(None); // Saving must not rebind an already running node.
}

fn assert_saved_start() {
    let consent = vpn::get_vpn_bypass_consent().expect("same data dir retains saved consent");
    let iface = physical_adapter();
    assert_eq!(consent.index, iface.index);
    start_real_node();
    assert_binding(Some(iface.name));
}

fn disable_after_start() {
    assert_saved_start();
    let binding = vpn::get_bind_interface();
    vpn::set_vpn_bypass_consent(None).unwrap();
    assert_eq!(vpn::get_vpn_bypass_consent(), None);
    assert_binding(binding); // Only the next process adopts the cleared setting.
}

fn assert_manual_override() {
    assert!(vpn::get_vpn_bypass_consent().is_some());
    let manual = "explicit-process-override".to_string();
    moss_ffi::set_bind_interface(Some(manual.clone()));
    shared_runtime::ensure_shared_resources().unwrap();
    assert_binding(Some(manual));
}
