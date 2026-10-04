use crate::*;

/// Neither a group nor a channel acks, so the only honest proof of transport
/// is a body written by somebody else.
pub(super) fn heard_a_stranger<'a>(
    own_fingerprint: &str,
    senders: impl Iterator<Item = &'a str>,
) -> bool {
    senders.into_iter().any(|from| from != own_fingerprint)
}

pub(super) fn group_listen(
    moss_lib: Option<std::path::PathBuf>,
    label: Option<String>,
    display_name: String,
    listen_port: u16,
    timeout_secs: u64,
    leave_after_heard: bool,
    linger_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "group-listen";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut groups = PrivateGroupRuntime::from_shared(runtime, store, None);

    let created = groups.create_group(CreateGroupRequest {
        label,
        display_name,
        listen_port,
        static_peer: None,
        org_pubkey: None,
    })?;
    // Same `invite` line shape as the DM listen: the runner greps one kind of
    // event whatever it is driving, and it is emitted before anything below
    // can fail.
    emit(
        role,
        "invite",
        serde_json::json!({
            "invite_uri": created.invite_uri,
            "group_id": created.group_id,
            "mesh_id": created.mesh_id,
            "fingerprint": created.fingerprint,
        }),
    );

    let group_id = created.group_id.clone();
    let heard = pump_until(Duration::from_secs(timeout_secs), || {
        let snap = groups.poll(&group_id)?;
        group_snapshot_line(role, &snap);
        Ok(heard_a_stranger(
            &snap.device_fingerprint,
            snap.messages.iter().map(|m| m.from_fingerprint.as_str()),
        ))
    })?;

    if heard && leave_after_heard {
        // The admin cannot commit its own removal, so this publishes a
        // self-removal proposal the successor commits (ADR 0023). Stay on the
        // mesh afterwards: the frame is best-effort and the room is closed.
        let left = groups.close(&group_id)?;
        emit(
            role,
            "left",
            serde_json::json!({ "group_id": left.group_id }),
        );
        pump_until(Duration::from_secs(linger_secs), || Ok(false))?;
        emit(
            role,
            "verdict",
            serde_json::json!({ "ok": true, "stage": "left" }),
        );
        return Ok(());
    }

    let snap = groups.poll(&group_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": heard,
            "stage": if heard { "received" } else { "receive" },
            "state": snap.state,
            "member_count": snap.member_count,
            "messages": snap.messages.len(),
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(heard)
}

pub(super) fn group_dial(
    moss_lib: Option<std::path::PathBuf>,
    invite: String,
    display_name: String,
    listen_port: u16,
    message: String,
    timeout_secs: u64,
    linger_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "group-dial";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut groups = PrivateGroupRuntime::from_shared(runtime, store, None);

    let joined = groups.join_group(JoinGroupRequest {
        invite_uri: invite,
        display_name,
        org_pubkey: None,
        listen_port,
        static_peer: None,
    })?;
    let group_id = joined.group_id.clone();
    emit(
        role,
        "accepted",
        serde_json::json!({ "group_id": group_id, "mesh_id": joined.mesh_id }),
    );

    let ready = pump_until(Duration::from_secs(timeout_secs), || {
        let snap = groups.poll(&group_id)?;
        group_snapshot_line(role, &snap);
        Ok(snap.state == "ready")
    })?;
    if !ready {
        let snap = groups.poll(&group_id)?;
        emit(
            role,
            "verdict",
            serde_json::json!({
                "ok": false,
                "stage": "mls_join",
                "state": snap.state,
                "member_count": snap.member_count,
                "flags": warn_flags(snap.mesh.as_ref()),
            }),
        );
        std::process::exit(1);
    }

    let sent = groups.send(&group_id, message)?;
    emit(
        role,
        "sent",
        serde_json::json!({
            "message_id": sent.message_id,
            "delivery_status": format!("{:?}", sent.delivery_status),
            "delivery_error": sent.delivery_error,
        }),
    );

    // A group settles at Sent the moment the frame is published, so this end
    // cannot tell whether it arrived. Stay on the mesh while the far end reads
    // it — quitting here takes the node down mid-flight and fails a run the
    // network would have completed.
    pump_until(Duration::from_secs(linger_secs), || {
        let snap = groups.poll(&group_id)?;
        group_snapshot_line(role, &snap);
        Ok(false)
    })?;

    let ok = sent.delivery_status != MessageDeliveryStatus::Failed;
    let snap = groups.poll(&group_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": ok,
            "stage": if ok { "sent" } else { "send" },
            "state": snap.state,
            "member_count": snap.member_count,
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(ok)
}
