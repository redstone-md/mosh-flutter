use crate::*;

pub(super) fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

/// Every line of output is one JSON object on stdout. Two probes' logs
/// concatenate and sort into a single timeline without any parsing rules
/// beyond "one object per line".
pub(super) fn emit(role: &str, kind: &str, body: serde_json::Value) {
    let line = serde_json::json!({
        "ts": now_ms(),
        "role": role,
        "kind": kind,
        "data": body,
    });
    println!("{line}");
}

/// The mesh facts worth a line every tick. All three kinds run on the same
/// node, so they report it the same way.
pub(super) fn mesh_json(mesh: Option<&MeshInfo>) -> serde_json::Value {
    let Some(m) = mesh else {
        return serde_json::Value::Null;
    };
    serde_json::json!({
        "advertised_addr": m.advertised_addr,
        "listen_port": m.listen_port,
        "nat_type": m.nat_type,
        "peer_count": m.peer_count,
        "direct_peer_count": m.direct_peer_count,
        "relayed_peer_count": m.relayed_peer_count,
        "relay_capable_peer_count": m.relay_capable_peer_count,
        "relay_route_count": m.relay_route_count,
        "known_peer_count": m.known_peer_count,
        "supernode_ready": m.supernode_ready,
        "channels": m.channels.len(),
    })
}

pub(super) fn events_json(events: &[SnapshotEvent]) -> serde_json::Value {
    serde_json::json!(events
        .iter()
        .map(|e| serde_json::json!({
            "name": e.event_name,
            "detail": e.detail_json,
            "at": e.epoch_millis,
        }))
        .collect::<Vec<_>>())
}

/// The subset of a snapshot worth a line every tick. The full snapshot carries
/// message bodies and attachment state that would drown the signal; these are
/// the fields that actually distinguish one failure from another.
pub(super) fn snapshot_line(role: &str, snap: &SessionSnapshot) {
    emit(
        role,
        "snapshot",
        serde_json::json!({
            "session_id": snap.session_id,
            "mesh_id": snap.mesh_id,
            "state": snap.state,
            "transport": snap.transport,
            "peer_display_name": snap.peer_display_name,
            "messages": snap.messages.len(),
            "mesh": mesh_json(snap.mesh.as_ref()),
            "events": events_json(&snap.events),
        }),
    );
}

/// `path` is a DM word — a group and a channel have one transport — but the
/// runner prints the same field for every role, so it carries the kind's own
/// transport story instead of a hole in the line.
pub(super) fn group_snapshot_line(role: &str, snap: &GroupSnapshot) {
    emit(
        role,
        "snapshot",
        serde_json::json!({
            "group_id": snap.group_id,
            "mesh_id": snap.mesh_id,
            "state": snap.state,
            "path": "mesh",
            "is_admin": snap.is_admin,
            "member_count": snap.member_count,
            "needs_rejoin": snap.needs_rejoin,
            "messages": snap.messages.len(),
            "mesh": mesh_json(snap.mesh.as_ref()),
            "events": events_json(&snap.events),
        }),
    );
}

pub(super) fn channel_snapshot_line(role: &str, snap: &ChannelSnapshot) {
    emit(
        role,
        "snapshot",
        serde_json::json!({
            "channel": snap.name,
            "topic": snap.topic,
            "mesh_id": snap.mesh_id,
            "state": "joined",
            "path": "mesh",
            "messages": snap.messages.len(),
            "mesh": mesh_json(snap.mesh.as_ref()),
            "events": events_json(&snap.events),
        }),
    );
}

/// A node whose advertised port differs from the port it bound is being
/// translated, which is what makes a hole punch impossible. Surfacing it as a
/// flag costs nothing and is invisible in the desktop UI today.
pub(super) fn warn_flags(mesh: Option<&MeshInfo>) -> Vec<&'static str> {
    let mut flags = Vec::new();
    let Some(mesh) = mesh else {
        return flags;
    };
    if mesh.relay_capable_peer_count == 0 {
        flags.push("no_relay_capable_peer");
    }
    if mesh.nat_type == "unknown" {
        flags.push("nat_unclassified");
    }
    if mesh.nat_type == "symmetric_nat" {
        flags.push("symmetric_nat");
    }
    if mesh.listen_port != 0 && !mesh.advertised_addr.is_empty() {
        let advertised_port = mesh
            .advertised_addr
            .rsplit_once(':')
            .and_then(|(_, p)| p.parse::<i32>().ok());
        if advertised_port.is_some_and(|p| p != mesh.listen_port) {
            flags.push("advertised_port_translated");
        }
    }
    flags
}

pub(super) fn report_interfaces(role: &str) {
    match network_inventory::list_interfaces() {
        Ok(interfaces) => {
            let rows: Vec<_> = interfaces
                .iter()
                .filter(|i| i.is_up && !i.is_loopback)
                .map(|i| {
                    serde_json::json!({
                        "name": i.name,
                        "description": i.description,
                        "index": i.index,
                        "ipv4": i.ipv4,
                        "is_virtual": i.is_virtual,
                        "is_vpn": i.is_vpn,
                        "is_default_route": i.is_default_route,
                    })
                })
                .collect();
            emit(role, "interfaces", serde_json::json!(rows));
        }
        Err(error) => emit(role, "interfaces_error", serde_json::json!(error)),
    }
}
