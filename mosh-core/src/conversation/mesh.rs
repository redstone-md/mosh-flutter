//! The mesh view and the event list every snapshot ends with.
//!
//! A snapshot of a DM, a group or a channel closes the same way: ask the node
//! how the mesh looks right now, then copy out the node events the diagnostics
//! panel shows. Neither part depends on the kind of conversation, so both live
//! here — the shapes and the two calls that build them.

use serde::{Deserialize, Serialize};

use crate::moss_ffi::{snapshot_event_log, MossEvent, MossNode};

/// One thing the node reported, as the diagnostics panel shows it.
#[derive(Debug, Clone, Serialize)]
pub struct SnapshotEvent {
    pub event_type: i32,
    pub event_name: String,
    pub detail_json: String,
    pub epoch_millis: u64,
}

impl SnapshotEvent {
    pub fn name_for(event_type: i32) -> &'static str {
        match event_type {
            1 => "peer_joined",
            2 => "peer_left",
            3 => "supernode_promoted",
            4 => "supernode_revoked",
            5 => "tracker_announce",
            6 => "tracker_failure",
            7 => "relay_migrated",
            8 => "message_delivered",
            9 => "message_read",
            10 => "typing",
            11 => "presence",
            _ => "unknown",
        }
    }
}

/// How the mesh looks to this node right now.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MeshInfo {
    #[serde(default)]
    pub mesh_id: String,
    #[serde(default)]
    pub listen_port: i32,
    #[serde(default)]
    pub advertised_addr: String,
    #[serde(default)]
    pub peer_count: i32,
    #[serde(default)]
    pub direct_peer_count: i32,
    #[serde(default)]
    pub relayed_peer_count: i32,
    #[serde(default)]
    pub relay_capable_peer_count: i32,
    #[serde(default)]
    pub relay_session_count: i32,
    #[serde(default)]
    pub relay_route_count: i32,
    #[serde(default)]
    pub known_peer_count: i32,
    #[serde(default)]
    pub channels: Vec<String>,
    #[serde(default)]
    pub nat_type: String,
    #[serde(default)]
    pub supernode_ready: bool,
    #[serde(default)]
    pub public_key: String,
    /// Per-peer identity of every currently connected peer. On the shared
    /// substrate a node connects network-wide, so `direct_peer_count` counts
    /// unrelated world peers; presence for one counterpart must match this list
    /// by `id` (the peer's moss public-key hex) instead of trusting a count.
    #[serde(default)]
    pub peer_details: Vec<PeerDetail>,
}

/// One connected peer, as the node names it.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PeerDetail {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub addr: String,
    #[serde(default)]
    pub relayed: bool,
}

/// How the mesh looks to this node. `None` when the node has nothing to
/// report, which is what a node that has not started yet gives back.
pub fn mesh_info(node: &MossNode) -> Option<MeshInfo> {
    let raw = node.mesh_info_json()?;
    read_mesh_info(&raw, || node.nat_type())
}

/// The node events the diagnostics panel shows, oldest first.
pub fn snapshot_events() -> Vec<SnapshotEvent> {
    name_events(snapshot_event_log())
}

/// The mesh report is missing the NAT type until the node has probed for it,
/// and the probe result is only on the node itself. Ask for it only when the
/// report has no answer of its own, so a snapshot costs one call and not two.
fn read_mesh_info(raw: &str, probe_nat: impl FnOnce() -> Option<String>) -> Option<MeshInfo> {
    let mut info: MeshInfo = serde_json::from_str(raw).ok()?;
    if info.nat_type.is_empty() {
        if let Some(nat) = probe_nat() {
            info.nat_type = nat;
        }
    }
    Some(info)
}

/// Moss reports an event as a number. The snapshot carries the name next to it
/// so the panel does not have to know the numbers.
fn name_events(events: Vec<MossEvent>) -> Vec<SnapshotEvent> {
    events
        .into_iter()
        .map(|event| SnapshotEvent {
            event_type: event.event_type,
            event_name: SnapshotEvent::name_for(event.event_type).to_string(),
            detail_json: event.detail_json,
            epoch_millis: event.epoch_millis,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_nat_type_is_filled_from_the_node() {
        let info = read_mesh_info(r#"{"nat_type":""}"#, || Some("full-cone".to_string()))
            .expect("valid report");

        assert_eq!(info.nat_type, "full-cone");
    }

    #[test]
    fn a_nat_type_in_the_report_wins() {
        let info = read_mesh_info(r#"{"nat_type":"symmetric"}"#, || {
            panic!("the node must not be asked when the report already answers")
        })
        .expect("valid report");

        assert_eq!(info.nat_type, "symmetric");
    }

    #[test]
    fn a_report_that_does_not_parse_is_no_report() {
        assert!(read_mesh_info("not json", || None).is_none());
    }

    #[test]
    fn every_event_carries_its_name() {
        let named = name_events(vec![
            MossEvent {
                event_type: 1,
                detail_json: "{}".to_string(),
                epoch_millis: 7,
            },
            // The messenger events moss added in v0.8.20 (codes 8-11). Mosh
            // does not act on them yet, but the diagnostics panel must not
            // render them as "unknown".
            MossEvent {
                event_type: 8,
                detail_json: "{}".to_string(),
                epoch_millis: 8,
            },
            MossEvent {
                event_type: 9,
                detail_json: "{}".to_string(),
                epoch_millis: 9,
            },
            MossEvent {
                event_type: 10,
                detail_json: "{}".to_string(),
                epoch_millis: 10,
            },
            MossEvent {
                event_type: 11,
                detail_json: "{}".to_string(),
                epoch_millis: 11,
            },
            MossEvent {
                event_type: 99,
                detail_json: "{}".to_string(),
                epoch_millis: 12,
            },
        ]);

        assert_eq!(named[0].event_name, "peer_joined");
        assert_eq!(named[0].event_type, 1);
        assert_eq!(named[0].epoch_millis, 7);
        assert_eq!(named[1].event_name, "message_delivered");
        assert_eq!(named[2].event_name, "message_read");
        assert_eq!(named[3].event_name, "typing");
        assert_eq!(named[4].event_name, "presence");
        assert_eq!(named[5].event_name, "unknown");
    }
}
