// Debug builds can exercise real Moss discovery in an isolated local network.
// Release builds do not compile this environment override.
use serde_json::json;
use url::Url;

pub(super) fn from_environment(config: String) -> String {
    let tracker = std::env::var("MOSH_TEST_TRACKER_URL").ok();
    let scope = tracker
        .as_ref()
        .and_then(|_| std::env::var("MOSH_TEST_NETWORK_SCOPE").ok())
        .map(|value| {
            value
                .parse()
                .expect("MOSH_TEST_NETWORK_SCOPE must be a u64")
        });
    configure(config, tracker.as_deref(), scope)
}

fn configure(config: String, tracker: Option<&str>, scope: Option<u64>) -> String {
    let Some(tracker) = tracker else {
        return config;
    };
    let tracker = Url::parse(tracker)
        .ok()
        .filter(is_local_tracker)
        .expect("MOSH_TEST_TRACKER_URL must be http://127.0.0.1:<port>/announce");
    let mut config: serde_json::Value =
        serde_json::from_str(&config).expect("Moss config must be valid JSON");
    config["trackers"] = json!([tracker.as_str()]);
    let port = tracker.port().unwrap();
    config["network_id"] = json!(match scope {
        Some(scope) => format!("mosh-ci-{port}-{scope}"),
        None => format!("mosh-ci-{port}"),
    });
    config["announce_interval_sec"] = json!(1);
    config["announce_jitter_sec"] = json!(1);
    config["dht_enabled"] = json!(false);
    config["lan_discovery_enabled"] = json!(false);
    for flag in [
        "upnp_enabled",
        "natpmp_enabled",
        "pcp_enabled",
        "port_prediction_enabled",
    ] {
        config["nat"][flag] = json!(false);
    }
    config.to_string()
}

fn is_local_tracker(tracker: &Url) -> bool {
    tracker.scheme() == "http"
        && tracker.host_str() == Some("127.0.0.1")
        && tracker.port().is_some_and(|port| port != 0)
        && tracker.path() == "/announce"
        && tracker.username().is_empty()
        && tracker.password().is_none()
        && tracker.query().is_none()
        && tracker.fragment().is_none()
}

#[cfg(test)]
mod tests {
    use super::configure;
    use serde_json::{json, Value};

    #[test]
    fn absent_tracker_keeps_the_default_config_byte_identical() {
        let config = "{\"listen_port\":17, \"lan_discovery_enabled\":true}".to_owned();
        assert_eq!(configure(config.clone(), None, None), config);
        assert_eq!(configure(config.clone(), None, Some(17)), config);
    }

    #[test]
    fn local_tracker_isolates_discovery_without_changing_node_settings() {
        let original = json!({
            "listen_port":17, "static_peers":[], "bind_interface":"Ethernet",
            "gossipsub":{"heartbeat_ms":250},
            "nat":{"upnp_enabled":true,"hole_punch_attempts":8},
            "debug":{"enabled":true,"record_path":"record.mossrec"}
        });
        let configured: Value = serde_json::from_str(&configure(
            original.to_string(),
            Some("http://127.0.0.1:31876/announce"),
            None,
        ))
        .unwrap();
        assert_eq!(
            configured["trackers"],
            json!(["http://127.0.0.1:31876/announce"])
        );
        assert_eq!(configured["network_id"], "mosh-ci-31876");
        assert_eq!(configured["announce_interval_sec"], 1);
        assert_eq!(configured["announce_jitter_sec"], 1);
        assert_eq!(configured["dht_enabled"], false);
        assert_eq!(configured["lan_discovery_enabled"], false);
        for field in [
            "listen_port",
            "static_peers",
            "bind_interface",
            "gossipsub",
            "debug",
        ] {
            assert_eq!(configured[field], original[field]);
        }
        assert_eq!(configured["nat"]["hole_punch_attempts"], 8);
        for field in [
            "upnp_enabled",
            "natpmp_enabled",
            "pcp_enabled",
            "port_prediction_enabled",
        ] {
            assert_eq!(configured["nat"][field], false);
        }
    }

    #[test]
    fn remote_and_malformed_trackers_are_rejected() {
        for tracker in [
            "",
            "https://127.0.0.1:31876/announce",
            "http://example.com:31876/announce",
            "http://localhost:31876/announce",
            "http://127.0.0.1/announce",
            "http://127.0.0.1:0/announce",
            "http://user:password@127.0.0.1:31876/announce",
            "http://127.0.0.1:31876/wrong",
            "http://127.0.0.1:31876/announce?x=1",
            "http://127.0.0.1:31876/announce#fragment",
        ] {
            assert!(
                std::panic::catch_unwind(|| configure("{}".to_owned(), Some(tracker), None))
                    .is_err()
            );
        }
    }

    #[test]
    fn scenarios_using_one_tracker_have_independent_discovery_networks() {
        let config = |scope| {
            serde_json::from_str::<Value>(&configure(
                "{}".to_owned(),
                Some("http://127.0.0.1:31876/announce"),
                Some(scope),
            ))
            .unwrap()
        };
        let first = config(17);
        let second = config(18);
        assert_ne!(first["network_id"], second["network_id"]);
        assert_eq!(first["trackers"], second["trackers"]);
    }

    #[test]
    fn independent_installations_in_one_scenario_share_discovery() {
        let config = |port| {
            serde_json::from_str::<Value>(&configure(
                json!({"listen_port":port}).to_string(),
                Some("http://127.0.0.1:31876/announce"),
                Some(17),
            ))
            .unwrap()
        };
        let first = config(12345);
        let second = config(12346);
        assert_eq!(first["network_id"], second["network_id"]);
        assert_ne!(first["listen_port"], second["listen_port"]);
    }
}
