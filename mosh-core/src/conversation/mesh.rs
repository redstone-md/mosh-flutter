//! The mesh view and the event list every snapshot ends with.
//!
//! A snapshot of a DM, a group or a channel closes the same way: ask the node
//! how the mesh looks right now, then copy out the node events the diagnostics
//! panel shows. Neither part depends on the kind of conversation, so both live
//! here and each runtime calls them.

use crate::moss_ffi::{snapshot_event_log, MossEvent, MossNode};
use crate::private_dm_runtime::{MeshInfo, SnapshotEvent};

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
            MossEvent {
                event_type: 99,
                detail_json: "{}".to_string(),
                epoch_millis: 8,
            },
        ]);

        assert_eq!(named[0].event_name, "peer_joined");
        assert_eq!(named[0].event_type, 1);
        assert_eq!(named[0].epoch_millis, 7);
        assert_eq!(named[1].event_name, "unknown");
    }
}
