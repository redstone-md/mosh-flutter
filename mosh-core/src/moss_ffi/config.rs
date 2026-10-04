//! Shared network overrides and node configuration.
use super::*;

static BIND_INTERFACE: RwLock<Option<String>> = RwLock::new(None);

pub fn set_bind_interface(value: Option<String>) {
    let mut guard = BIND_INTERFACE
        .write()
        .expect("bind interface lock poisoned");
    *guard = value.filter(|s| !s.is_empty());
}

/// Read the current app-wide bind interface for diagnostics or UI display.
pub fn current_bind_interface() -> Option<String> {
    BIND_INTERFACE
        .read()
        .expect("bind interface lock poisoned")
        .clone()
}

pub fn node_config_json(config: &MossNodeConfig) -> String {
    let mut value = serde_json::json!({
        "listen_port": config.listen_port,
        "static_peers": config.static_peer.iter().collect::<Vec<_>>(),
        "announce_interval_sec": 15,
        "bootstrap_timeout_sec": 12,
        "lan_discovery_enabled": true,
        "gossipsub": { "heartbeat_ms": 250 },
        "nat": {
            "upnp_enabled": true, "natpmp_enabled": true, "pcp_enabled": true,
            "hole_punch_attempts": 8, "port_prediction_enabled": true,
        },
    });
    if let Some(bind) = config
        .bind_interface
        .clone()
        .filter(|name| !name.is_empty())
        .or_else(current_bind_interface)
    {
        value["bind_interface"] = bind.into();
    }
    // Host-requested debug recordings stay off in shipping defaults.
    if let Some(dir) = std::env::var("MOSH_DEBUG_RECORD_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())
    {
        value["debug"] = serde_json::json!({
            "enabled": true,
            "record_path": format!("{dir}/moss-debug-{}.mossrec", std::process::id()),
            "record_max_mb": 64,
            "record_every_sec": 5,
        });
    }
    let config = value.to_string();
    #[cfg(debug_assertions)]
    let config = test_network::from_environment(config);
    config
}
