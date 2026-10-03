use crate::*;

/// What moss answers when it has nobody to hand the frame to (ADR 0021): the
/// send lands as `Failed` carrying the refusal text, and the frame never left
/// the device — which is exactly what a retry is for. Any other failure is a
/// real transport fault and stops the loop.
pub(super) fn refused_for_no_peers(sent: &ChannelSendResult) -> bool {
    sent.delivery_status == MessageDeliveryStatus::Failed
        && sent
            .delivery_error
            .as_deref()
            .is_some_and(|error| error.contains(NO_PEERS_TEXT))
}

/// Re-drives a channel send that moss refused for want of peers, once per
/// tick, until a publish is accepted or the budget is spent (issue #3). Every
/// attempt lands in the timeline next to the mesh facts, so rendezvous
/// latency is readable from it. A refused send keeps its attempt record in
/// the outbox, so the retry replays the same message id and bytes — the
/// listener sees one message no matter how many refusals came first.
/// `watch_only` keeps the old `--send-without-peers` meaning: one attempt,
/// watch the refusal, never retry.
pub(super) fn retry_send_until_accepted(
    role: &str,
    channels: &mut ChannelRuntime,
    channel: &str,
    first: ChannelSendResult,
    budget: Duration,
    watch_only: bool,
) -> Result<ChannelSendResult, Box<dyn std::error::Error>> {
    let mut attempt = 1u32;
    let started = std::time::Instant::now();
    let mut sent = first;
    emit(
        role,
        "sent",
        serde_json::json!({
            "message_id": sent.message_id,
            "delivery_status": format!("{:?}", sent.delivery_status),
            "delivery_error": sent.delivery_error,
            "attempt": attempt,
        }),
    );
    while !watch_only && refused_for_no_peers(&sent) {
        let remaining = budget.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            break;
        }
        // Pace the re-drives one per tick: the refusal takes a tick to come
        // back, and polling here keeps the runtime's state machine advancing
        // with the mesh facts in the timeline while the rendezvous forms.
        std::thread::sleep(TICK.min(remaining));
        let snap = channels.poll(channel)?;
        channel_snapshot_line(role, &snap);
        sent = channels.retry_message(channel, &sent.message_id)?;
        attempt += 1;
        emit(
            role,
            "send_retry",
            serde_json::json!({
                "attempt": attempt,
                "elapsed_ms": started.elapsed().as_millis(),
                "message_id": sent.message_id,
                "delivery_status": format!("{:?}", sent.delivery_status),
                "delivery_error": sent.delivery_error,
            }),
        );
    }
    Ok(sent)
}

/// Both channel ends run the same bootstrap: load the runtime, join by name,
/// and announce the room. A channel has no invite to hand over — both ends
/// agree on the name up front — so this line only says the room is open.
pub(super) fn channel_join(
    moss_lib: Option<std::path::PathBuf>,
    role: &str,
    channel: &str,
    display_name: String,
    listen_port: u16,
) -> Result<ChannelRuntime, Box<dyn std::error::Error>> {
    let (runtime, store) = resources(role, moss_lib)?;
    let mut channels = ChannelRuntime::from_shared(runtime, store, None);

    let joined = channels.join(JoinChannelRequest {
        name: channel.to_string(),
        display_name,
        listen_port,
        static_peer: None,
    })?;
    emit(
        role,
        "joined",
        serde_json::json!({
            "channel": joined.name,
            "mesh_id": joined.mesh_id,
            "fingerprint": joined.device_fingerprint,
        }),
    );
    Ok(channels)
}

pub(super) fn channel_listen(
    moss_lib: Option<std::path::PathBuf>,
    channel: String,
    display_name: String,
    listen_port: u16,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "channel-listen";
    let mut channels = channel_join(moss_lib, role, &channel, display_name, listen_port)?;

    let heard = pump_until(Duration::from_secs(timeout_secs), || {
        let snap = channels.poll(&channel)?;
        channel_snapshot_line(role, &snap);
        Ok(heard_a_stranger(
            &snap.device_fingerprint,
            snap.messages.iter().map(|m| m.from_fingerprint.as_str()),
        ))
    })?;

    let snap = channels.poll(&channel)?;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": heard,
            "stage": if heard { "received" } else { "receive" },
            "messages": snap.messages.len(),
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(heard)
}

// The CLI hands clap-parsed fields straight through, one parameter per
// `ChannelDial` flag; the arity is the command surface, not a design smell.
// Pre-existing signature (the ticket only changed the body).
#[allow(clippy::too_many_arguments)]
pub(super) fn channel_dial(
    moss_lib: Option<std::path::PathBuf>,
    channel: String,
    display_name: String,
    listen_port: u16,
    message: String,
    timeout_secs: u64,
    linger_secs: u64,
    send_without_peers: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "channel-dial";
    let mut channels = channel_join(moss_lib, role, &channel, display_name, listen_port)?;

    // There is no handshake to wait on here, and waiting for "any substrate
    // peer" measured the wrong thing: a substrate peer is a stranger, not a
    // channel member (issue #3). The send itself is the rendezvous probe:
    // send now, and when moss answers "no peers yet" — the frame never left
    // the device — re-drive the same message every tick until the budget is
    // spent or a publish is accepted.
    let first = channels.send(&channel, message)?;
    let sent = retry_send_until_accepted(
        role,
        &mut channels,
        &channel,
        first,
        Duration::from_secs(timeout_secs),
        send_without_peers,
    )?;

    pump_until(Duration::from_secs(linger_secs), || {
        let snap = channels.poll(&channel)?;
        channel_snapshot_line(role, &snap);
        Ok(false)
    })?;

    settle_dial_verdict(role, &sent, channels.poll(&channel)?)
}

/// The dial-end verdict: what moss told this end about its own frame, plus
/// one last look at the room. A dial can only ever report that the frame was
/// accepted and left the device — whether it was heard is the listening end's
/// verdict (channel_listen above), same as a group.
pub(super) fn settle_dial_verdict(
    role: &str,
    sent: &ChannelSendResult,
    snap: ChannelSnapshot,
) -> Result<(), Box<dyn std::error::Error>> {
    let ok = sent.delivery_status != MessageDeliveryStatus::Failed;
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": ok,
            "stage": if ok { "sent" } else { "send" },
            "messages": snap.messages.len(),
            "flags": warn_flags(snap.mesh.as_ref()),
        }),
    );
    finish(ok)
}
