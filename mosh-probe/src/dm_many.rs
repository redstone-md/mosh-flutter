use crate::*;

pub(super) fn dial_many(
    moss_lib: Option<std::path::PathBuf>,
    invites: Vec<String>,
    display_name: String,
    listen_port: u16,
    message: String,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "dial-many";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);

    let mut session_ids = Vec::new();
    for invite in invites {
        let accepted = dm.accept_invite(AcceptInviteRequest {
            invite_uri: invite,
            display_name: display_name.clone(),
            listen_port,
            static_peer: None,
        })?;
        emit(
            role,
            "accepted",
            serde_json::json!({
                "session_id": accepted.session_id,
                "mesh_id": accepted.mesh_id,
            }),
        );
        session_ids.push(accepted.session_id);
    }

    let budget = Duration::from_secs(timeout_secs);
    let started = std::time::Instant::now();
    let ready = pump_all(role, &mut dm, &session_ids, budget, |snap| {
        snap.state == DmSessionState::Connected
    })?;

    // One node or N is visible from here: every session reports the port of the
    // node carrying it, so N distinct ports means N nodes under one identity —
    // the thing that used to break the second conversation.
    let distinct_nodes = topology(role, &mut dm, &session_ids);

    if !ready {
        emit(
            role,
            "verdict",
            serde_json::json!({ "ok": false, "stage": "mls_handshake" }),
        );
        std::process::exit(1);
    }

    let mut sent_ids = Vec::new();
    for session_id in &session_ids {
        let sent = dm.send_message(session_id, message.clone())?;
        emit(
            role,
            "sent",
            serde_json::json!({ "session_id": session_id, "message_id": sent.message_id }),
        );
        sent_ids.push(sent.message_id);
    }

    let remaining = budget.saturating_sub(started.elapsed());
    let delivered = pump_all(role, &mut dm, &session_ids, remaining, |snap| {
        snap.messages.iter().any(|message| {
            sent_ids
                .iter()
                .any(|id| message.message_id.as_deref() == Some(id.as_str()))
                && message.delivery_status == Some(MessageDeliveryStatus::Delivered)
        })
    })?;

    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": delivered && distinct_nodes == 1,
            "stage": if delivered { "delivered" } else { "delivery" },
            "sessions": session_ids.len(),
            "distinct_nodes": distinct_nodes,
        }),
    );
    finish(delivered && distinct_nodes == 1)
}

pub(super) fn listen_many(
    moss_lib: Option<std::path::PathBuf>,
    sessions: usize,
    display_name: String,
    listen_port: u16,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "listen-many";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);

    let mut session_ids = Vec::new();
    for index in 0..sessions {
        let created = dm.create_invite(StartSessionRequest {
            display_name: format!("{display_name}-{index}"),
            // Only the first invite picks the port; they all land on the same
            // node, which is the point.
            listen_port: if index == 0 { listen_port } else { 0 },
            static_peer: None,
        })?;
        // The runner greps these to hand every URI to the other end, so they
        // are emitted before anything downstream can fail.
        emit(
            role,
            "invite",
            serde_json::json!({
                "index": index,
                "invite_uri": created.invite_uri,
                "session_id": created.session_id,
                "mesh_id": created.mesh_id,
            }),
        );
        session_ids.push(created.session_id);
    }

    let ready = pump_all(
        role,
        &mut dm,
        &session_ids,
        Duration::from_secs(timeout_secs),
        |snap| snap.state == DmSessionState::Connected && !snap.messages.is_empty(),
    )?;

    let distinct_nodes = topology(role, &mut dm, &session_ids);
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": ready && distinct_nodes == 1,
            "sessions": session_ids.len(),
            "distinct_nodes": distinct_nodes,
        }),
    );
    finish(ready && distinct_nodes == 1)
}

fn topology(role: &str, dm: &mut PrivateDmRuntime, ids: &[String]) -> usize {
    let ports: Vec<_> = ids
        .iter()
        .filter_map(|id| dm.poll_session(id).ok())
        .filter_map(|snapshot| snapshot.mesh.map(|mesh| mesh.listen_port))
        .collect();
    let mut unique = ports.clone();
    unique.sort_unstable();
    unique.dedup();
    emit(
        role,
        "topology",
        serde_json::json!({
            "sessions": ids.len(),
            "listen_ports": ports,
            "distinct_nodes": unique.len(),
        }),
    );
    unique.len()
}
