use crate::*;

pub(super) fn listen(
    moss_lib: Option<std::path::PathBuf>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "listen";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);

    let created = dm.create_invite(StartSessionRequest {
        display_name,
        listen_port,
        static_peer,
    })?;
    // The runner script greps this line to hand the URI to the other end, so
    // it is emitted before anything can fail downstream.
    emit(
        role,
        "invite",
        serde_json::json!({
            "invite_uri": created.invite_uri,
            "session_id": created.session_id,
            "mesh_id": created.mesh_id,
            "fingerprint": created.fingerprint,
            "listen_address": created.listen_address,
        }),
    );

    let ready = pump(
        role,
        &mut dm,
        &created.session_id,
        Duration::from_secs(timeout_secs),
        |snap| snap.state == DmSessionState::Connected && !snap.messages.is_empty(),
    )?;

    let snap = dm.poll_session(&created.session_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": ready,
            "state": snap.state,
            "transport": snap.transport,
            "messages": snap.messages.len(),
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(ready)
}

pub(super) fn dial(
    moss_lib: Option<std::path::PathBuf>,
    invite: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
    message: String,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "dial";
    let (runtime, store) = resources(role, moss_lib)?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);

    let accepted = dm.accept_invite(AcceptInviteRequest {
        invite_uri: invite,
        display_name,
        listen_port,
        static_peer,
    })?;
    emit(
        role,
        "accepted",
        serde_json::json!({ "session_id": accepted.session_id, "mesh_id": accepted.mesh_id }),
    );

    let budget = Duration::from_secs(timeout_secs);
    let started = std::time::Instant::now();
    let ready = pump(role, &mut dm, &accepted.session_id, budget, |snap| {
        snap.state == DmSessionState::Connected
    })?;
    if !ready {
        let snap = dm.poll_session(&accepted.session_id)?;
        emit(
            role,
            "verdict",
            serde_json::json!({
                "ok": false,
                "stage": "mls_handshake",
                "state": snap.state,
                "transport": snap.transport,
                "flags": warn_flags(snap.mesh.as_ref()),
            }),
        );
        std::process::exit(1);
    }

    let sent = dm.send_message(&accepted.session_id, message)?;
    emit(
        role,
        "sent",
        serde_json::json!({ "message_id": sent.message_id }),
    );

    // Whatever is left of the budget after the handshake belongs to delivery.
    let remaining = budget.saturating_sub(started.elapsed());
    let delivered = pump(role, &mut dm, &accepted.session_id, remaining, |snap| {
        snap.messages.iter().any(|m| {
            m.message_id.as_deref() == Some(sent.message_id.as_str())
                && m.delivery_status == Some(MessageDeliveryStatus::Delivered)
        })
    })?;

    let snap = dm.poll_session(&accepted.session_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": delivered,
            "stage": if delivered { "delivered" } else { "delivery" },
            "state": snap.state,
            "transport": snap.transport,
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(delivered)
}
