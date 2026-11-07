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
        "explicit_retry_max_sec": 30,
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

/// A port currently free for both TCP and UDP (their port spaces are
/// separate), or 0 to let Moss pick when no probe succeeds. Hand Moss this
/// rather than 0: its default Masq listener binds TCP first, then UDP on that
/// number, which Windows can forbid. The port is released before Moss binds
/// it, so a racer can still take it; the shared node retries its start.
pub fn dual_protocol_port() -> u16 {
    const PROBE_ATTEMPTS: usize = 16;
    (0..PROBE_ATTEMPTS)
        .find_map(|_| {
            // Probe UDP first: on Windows, the OS ephemeral UDP allocator avoids
            // excluded ranges (e.g. WinNAT/Hyper-V), whereas probing TCP first can
            // return a port that is forbidden for UDP (WSAEACCES 10013).
            let udp = std::net::UdpSocket::bind(("0.0.0.0", 0)).ok()?;
            let port = udp.local_addr().ok()?.port();
            let tcp = std::net::TcpListener::bind(("0.0.0.0", port)).ok()?;
            drop(tcp);
            drop(udp);
            Some(port)
        })
        .unwrap_or(0)
}
