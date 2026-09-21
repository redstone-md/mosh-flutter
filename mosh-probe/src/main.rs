//! Two-ended reachability probe for the Mosh DM stack.
//!
//! The desktop app is the only way to exercise this code path today, which
//! makes every diagnosis a screenshot-reading exercise across two humans. This
//! binary drives the same adapters headlessly so one end can sit on a server
//! and the other on a laptop, and both emit a machine-readable timeline that
//! merges into a single ordered story.
//!
//! `doctor` reports local facts and exits; every other subcommand is one half
//! of a two-ended run. `listen`/`dial` drive a DM, `group-listen`/`group-dial`
//! a private group, `channel-listen`/`channel-dial` a public channel.
//!
//! Only a DM acks a message, so only a DM can call itself delivered from the
//! sending end. A group and a channel settle at `Sent` the moment the frame
//! leaves, which proves nothing about transport — so their verdict lives on
//! the LISTENING end, which passes when it sees a body from someone else.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use mosh_core::attachment_store::AttachmentStore;
use mosh_core::channel_runtime::{
    ChannelRuntime, ChannelSendResult, ChannelSnapshot, JoinChannelRequest,
};
use mosh_core::conversation::mesh::{MeshInfo, SnapshotEvent};
use mosh_core::moss_ffi::MossFfiRuntime;
use mosh_core::moss_runtime::{MossDynamicRuntime, MossRuntime};
use mosh_core::network_inventory;
use mosh_core::outbound_delivery::MessageDeliveryStatus;
use mosh_core::private_dm_runtime::{
    AcceptInviteRequest, DmSessionState, PrivateDmRuntime, SessionSnapshot, StartSessionRequest,
};
use mosh_core::private_group_runtime::{
    CreateGroupRequest, GroupSnapshot, JoinGroupRequest, PrivateGroupRuntime,
};

/// How often the poll loop ticks. `poll_session` is what drives the runtime's
/// state machine — nothing advances between calls — so this doubles as the
/// runtime's heartbeat, not just a sampling rate.
const TICK: Duration = Duration::from_millis(500);

/// The text moss puts behind a publish with nobody to publish to (ADR 0021).
/// Matching on a fragment is the honest test: it is the same wording the
/// runtime regression-tests pin, so the two cannot drift apart silently.
const NO_PEERS_TEXT: &str = "no peers yet, so the message did not go out";

#[derive(Parser)]
#[command(
    name = "mosh-probe",
    about = "Headless two-ended reachability probe for the Mosh DM stack"
)]
struct Cli {
    /// Explicit path to the moss shared library. Defaults to the same
    /// candidate search the desktop app uses.
    #[arg(long, global = true)]
    moss_lib: Option<std::path::PathBuf>,

    /// Bind moss to a specific network interface, mirroring the desktop app's
    /// VPN-bypass toggle. Pass the adapter name exactly as `doctor` prints it.
    #[arg(long, global = true)]
    bind_interface: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print local network, library and node facts, then exit.
    Doctor {
        /// Also start a throwaway node and report what it observes about
        /// itself. Costs a few seconds; skip it for a pure offline check.
        #[arg(long)]
        with_node: bool,
        /// Port for the throwaway node. 0 lets the OS choose.
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
    },
    /// Create an invite, print it, and wait for the peer to complete MLS.
    Listen {
        #[arg(long, default_value = "probe-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long)]
        static_peer: Option<String>,
        /// Give up after this many seconds.
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Create SEVERAL invites from one process and wait for every one of them
    /// to complete.
    ///
    /// The counterpart to `dial-many`, and the reason it exists: running N
    /// separate `listen` processes on one host puts N nodes behind one address,
    /// which is the very shape this work removed. A test whose far end
    /// reproduces the defect cannot measure the fix. One process, N rooms, on
    /// both ends.
    ListenMany {
        #[arg(long, default_value_t = 2)]
        sessions: usize,
        #[arg(long, default_value = "probe-listen-many")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Accept SEVERAL invites in one process, then send on each and require
    /// every one to be delivered.
    ///
    /// This is the shape the desktop app actually has and `dial` does not: one
    /// process, one identity, several conversations at once. Each session used
    /// to start its own moss node, so N conversations meant N nodes sharing one
    /// peer id — a remote peer keeps one connection per identity and closed the
    /// rest, which is why a chat only worked once every other chat was closed.
    /// One `dial` can never show that; N concurrent ones can.
    DialMany {
        /// Repeat once per invite.
        #[arg(long = "invite", required = true)]
        invites: Vec<String>,
        #[arg(long, default_value = "probe-dial-many")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Accept an invite, then send a message and wait for it to be delivered.
    Dial {
        #[arg(long)]
        invite: String,
        #[arg(long, default_value = "probe-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long)]
        static_peer: Option<String>,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Create a private group, print its invite, and wait to hear a message
    /// from whoever joins. This end owns the verdict: a group has no delivery
    /// receipt, so being received is the only proof the frame crossed.
    GroupListen {
        #[arg(long)]
        label: Option<String>,
        #[arg(long, default_value = "probe-group-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        /// Leave the group once the message is heard, so the far end can be
        /// watched taking over as admin (ADR 0023).
        #[arg(long, default_value_t = false)]
        leave_after_heard: bool,
        /// Stay on the mesh this long after leaving, so the departure frame
        /// goes out before the node does.
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
    },
    /// Join a private group from its invite, then send one message.
    GroupDial {
        #[arg(long)]
        invite: String,
        #[arg(long, default_value = "probe-group-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        /// Stay on the mesh this long after sending. Leaving immediately takes
        /// the node down while the frame is still in flight.
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
    },
    /// Join a public channel and wait to hear a message from anyone else.
    ChannelListen {
        #[arg(long)]
        channel: String,
        #[arg(long, default_value = "probe-channel-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Join a public channel and send one message into it.
    ChannelDial {
        #[arg(long)]
        channel: String,
        #[arg(long, default_value = "probe-channel-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
        /// Send straight away and stop after one attempt, to watch what a
        /// publish with nobody to publish to reports. Expect a Failed send.
        /// The default is the opposite: the send retries on that refusal
        /// until the budget is spent.
        #[arg(long, default_value_t = false)]
        send_without_peers: bool,
    },
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

/// Every line of output is one JSON object on stdout. Two probes' logs
/// concatenate and sort into a single timeline without any parsing rules
/// beyond "one object per line".
fn emit(role: &str, kind: &str, body: serde_json::Value) {
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
fn mesh_json(mesh: Option<&MeshInfo>) -> serde_json::Value {
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

fn events_json(events: &[SnapshotEvent]) -> serde_json::Value {
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
fn snapshot_line(role: &str, snap: &SessionSnapshot) {
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
fn group_snapshot_line(role: &str, snap: &GroupSnapshot) {
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

fn channel_snapshot_line(role: &str, snap: &ChannelSnapshot) {
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
fn warn_flags(mesh: Option<&MeshInfo>) -> Vec<&'static str> {
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

fn load_runtime(
    moss_lib: Option<std::path::PathBuf>,
) -> Result<Arc<MossFfiRuntime>, Box<dyn std::error::Error>> {
    let runtime = match moss_lib {
        Some(path) => MossFfiRuntime::load_from_path(&path)?,
        None => MossFfiRuntime::load_default()?,
    };
    Ok(Arc::new(runtime))
}

/// The attachment store is required by the DM runtime but irrelevant to a
/// reachability probe, so it lives in a temp dir nobody has to clean up.
fn scratch_store() -> Result<Arc<AttachmentStore>, Box<dyn std::error::Error>> {
    let mut path = std::env::temp_dir();
    path.push(format!("mosh-probe-attachments-{}", std::process::id()));
    Ok(Arc::new(AttachmentStore::new(&path)?))
}

fn report_interfaces(role: &str) {
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

fn doctor(
    moss_lib: Option<std::path::PathBuf>,
    bind_interface: Option<String>,
    with_node: bool,
    listen_port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "doctor";
    report_interfaces(role);

    let status = MossDynamicRuntime::from_default_candidates().status();
    emit(
        role,
        "moss_library",
        serde_json::json!({
            "link_mode": status.link_mode,
            "library_name": status.library_name,
            "available": status.available,
            "checked_paths": status.checked_paths,
            "required_symbols": status.required_symbols,
        }),
    );

    emit(
        role,
        "bind_interface",
        serde_json::json!({
            "requested": bind_interface,
            "effective": mosh_core::moss_ffi::current_bind_interface(),
        }),
    );

    if !with_node {
        return Ok(());
    }

    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);
    let created = dm.create_invite(StartSessionRequest {
        display_name: "probe-doctor".to_string(),
        listen_port,
        static_peer: None,
    })?;
    emit(
        role,
        "node_started",
        serde_json::json!({ "mesh_id": created.mesh_id, "listen_address": created.listen_address }),
    );

    // A node needs a moment to bind, probe STUN and pick up its first peers;
    // sampling immediately would only ever report "unknown".
    for _ in 0..20 {
        std::thread::sleep(TICK);
        let snap = dm.poll_session(&created.session_id)?;
        snapshot_line(role, &snap);
    }
    let snap = dm.poll_session(&created.session_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({ "flags": warn_flags(snap.mesh.as_ref()) }),
    );
    Ok(())
}

/// The tick loop every kind runs on. `step` polls its own runtime, emits its
/// own snapshot line, and answers whether the goal is reached; nothing here
/// knows what a conversation is.
fn pump_until(
    timeout: Duration,
    mut step: impl FnMut() -> Result<bool, Box<dyn std::error::Error>>,
) -> Result<bool, Box<dyn std::error::Error>> {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        if step()? {
            return Ok(true);
        }
        std::thread::sleep(TICK);
    }
    Ok(false)
}

/// Drives the runtime until `done` is satisfied or the budget runs out,
/// emitting one snapshot line per tick. Returns whether `done` was reached.
fn pump(
    role: &str,
    dm: &mut PrivateDmRuntime,
    session_id: &str,
    timeout: Duration,
    mut done: impl FnMut(&SessionSnapshot) -> bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    pump_until(timeout, || {
        let snap = dm.poll_session(session_id)?;
        snapshot_line(role, &snap);
        Ok(done(&snap))
    })
}

/// `pump` across several sessions at once: one snapshot line per session per
/// tick, finishing only when EVERY session satisfies `done`. Concurrency is the
/// point — checking them one after another would let an earlier session finish
/// and go quiet while a later one is still starting.
fn pump_all(
    role: &str,
    dm: &mut PrivateDmRuntime,
    session_ids: &[String],
    timeout: Duration,
    mut done: impl FnMut(&SessionSnapshot) -> bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    pump_until(timeout, || {
        let mut all = true;
        for session_id in session_ids {
            let snap = dm.poll_session(session_id)?;
            snapshot_line(role, &snap);
            if !done(&snap) {
                all = false;
            }
        }
        Ok(all)
    })
}

fn dial_many(
    moss_lib: Option<std::path::PathBuf>,
    invites: Vec<String>,
    display_name: String,
    listen_port: u16,
    message: String,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "dial-many";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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
    let ports: Vec<i32> = session_ids
        .iter()
        .filter_map(|id| dm.poll_session(id).ok())
        .filter_map(|snap| snap.mesh.map(|mesh| mesh.listen_port))
        .collect();
    let mut distinct = ports.clone();
    distinct.sort_unstable();
    distinct.dedup();
    emit(
        role,
        "topology",
        serde_json::json!({
            "sessions": session_ids.len(),
            "listen_ports": ports,
            "distinct_nodes": distinct.len(),
        }),
    );

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
                && format!("{:?}", message.delivery_status).contains("Delivered")
        })
    })?;

    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": delivered && distinct.len() == 1,
            "stage": if delivered { "delivered" } else { "delivery" },
            "sessions": session_ids.len(),
            "distinct_nodes": distinct.len(),
        }),
    );
    if !delivered || distinct.len() != 1 {
        std::process::exit(1);
    }
    Ok(())
}

fn listen_many(
    moss_lib: Option<std::path::PathBuf>,
    sessions: usize,
    display_name: String,
    listen_port: u16,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "listen-many";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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

    let ports: Vec<i32> = session_ids
        .iter()
        .filter_map(|id| dm.poll_session(id).ok())
        .filter_map(|snap| snap.mesh.map(|mesh| mesh.listen_port))
        .collect();
    let mut distinct = ports.clone();
    distinct.sort_unstable();
    distinct.dedup();
    emit(
        role,
        "topology",
        serde_json::json!({
            "sessions": session_ids.len(),
            "listen_ports": ports,
            "distinct_nodes": distinct.len(),
        }),
    );
    emit(
        role,
        "verdict",
        serde_json::json!({
            "ok": ready && distinct.len() == 1,
            "sessions": session_ids.len(),
            "distinct_nodes": distinct.len(),
        }),
    );
    if !ready || distinct.len() != 1 {
        std::process::exit(1);
    }
    Ok(())
}

fn listen(
    moss_lib: Option<std::path::PathBuf>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "listen";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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
    if !ready {
        std::process::exit(1);
    }
    Ok(())
}

fn dial(
    moss_lib: Option<std::path::PathBuf>,
    invite: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
    message: String,
    timeout_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "dial";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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
                && format!("{:?}", m.delivery_status).contains("Delivered")
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
    if !delivered {
        std::process::exit(1);
    }
    Ok(())
}

/// Neither a group nor a channel acks, so the only honest proof of transport
/// is a body written by somebody else.
fn heard_a_stranger<'a>(own_fingerprint: &str, senders: impl Iterator<Item = &'a str>) -> bool {
    senders.into_iter().any(|from| from != own_fingerprint)
}

/// What moss answers when it has nobody to hand the frame to (ADR 0021): the
/// send lands as `Failed` carrying the refusal text, and the frame never left
/// the device — which is exactly what a retry is for. Any other failure is a
/// real transport fault and stops the loop.
fn refused_for_no_peers(sent: &ChannelSendResult) -> bool {
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
fn retry_send_until_accepted(
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

fn group_listen(
    moss_lib: Option<std::path::PathBuf>,
    label: Option<String>,
    display_name: String,
    listen_port: u16,
    timeout_secs: u64,
    leave_after_heard: bool,
    linger_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "group-listen";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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
    if !heard {
        std::process::exit(1);
    }
    Ok(())
}

fn group_dial(
    moss_lib: Option<std::path::PathBuf>,
    invite: String,
    display_name: String,
    listen_port: u16,
    message: String,
    timeout_secs: u64,
    linger_secs: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "group-dial";
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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
    if !ok {
        std::process::exit(1);
    }
    Ok(())
}

/// Both channel ends run the same bootstrap: load the runtime, join by name,
/// and announce the room. A channel has no invite to hand over — both ends
/// agree on the name up front — so this line only says the room is open.
fn channel_join(
    moss_lib: Option<std::path::PathBuf>,
    role: &str,
    channel: &str,
    display_name: String,
    listen_port: u16,
) -> Result<ChannelRuntime, Box<dyn std::error::Error>> {
    report_interfaces(role);
    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
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

fn channel_listen(
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
    if !heard {
        std::process::exit(1);
    }
    Ok(())
}

// The CLI hands clap-parsed fields straight through, one parameter per
// `ChannelDial` flag; the arity is the command surface, not a design smell.
// Pre-existing signature (the ticket only changed the body).
#[allow(clippy::too_many_arguments)]
fn channel_dial(
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
fn settle_dial_verdict(
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
    if !ok {
        std::process::exit(1);
    }
    Ok(())
}

fn main() {
    let cli = Cli::parse();
    if let Some(name) = cli.bind_interface.clone() {
        mosh_core::moss_ffi::set_bind_interface(Some(name));
    }

    let result = match cli.command {
        Command::Doctor {
            with_node,
            listen_port,
        } => doctor(cli.moss_lib, cli.bind_interface, with_node, listen_port),
        Command::Listen {
            display_name,
            listen_port,
            static_peer,
            timeout_secs,
        } => listen(
            cli.moss_lib,
            display_name,
            listen_port,
            static_peer,
            timeout_secs,
        ),
        Command::ListenMany {
            sessions,
            display_name,
            listen_port,
            timeout_secs,
        } => listen_many(
            cli.moss_lib,
            sessions,
            display_name,
            listen_port,
            timeout_secs,
        ),
        Command::DialMany {
            invites,
            display_name,
            listen_port,
            message,
            timeout_secs,
        } => dial_many(
            cli.moss_lib,
            invites,
            display_name,
            listen_port,
            message,
            timeout_secs,
        ),
        Command::Dial {
            invite,
            display_name,
            listen_port,
            static_peer,
            message,
            timeout_secs,
        } => dial(
            cli.moss_lib,
            invite,
            display_name,
            listen_port,
            static_peer,
            message,
            timeout_secs,
        ),
        Command::GroupListen {
            label,
            display_name,
            listen_port,
            timeout_secs,
            leave_after_heard,
            linger_secs,
        } => group_listen(
            cli.moss_lib,
            label,
            display_name,
            listen_port,
            timeout_secs,
            leave_after_heard,
            linger_secs,
        ),
        Command::GroupDial {
            invite,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
        } => group_dial(
            cli.moss_lib,
            invite,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
        ),
        Command::ChannelListen {
            channel,
            display_name,
            listen_port,
            timeout_secs,
        } => channel_listen(
            cli.moss_lib,
            channel,
            display_name,
            listen_port,
            timeout_secs,
        ),
        Command::ChannelDial {
            channel,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
            send_without_peers,
        } => channel_dial(
            cli.moss_lib,
            channel,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
            send_without_peers,
        ),
    };

    if let Err(error) = result {
        emit("probe", "error", serde_json::json!(error.to_string()));
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mosh_core::outbound_delivery::MessageDeliveryStatus;

    fn send_result(status: MessageDeliveryStatus, error: Option<&str>) -> ChannelSendResult {
        ChannelSendResult {
            name: "probe-channel".to_string(),
            bytes: 0,
            message_id: "m-1".to_string(),
            sent_at_ms: 0,
            delivery_status: status,
            delivery_error: error.map(|e| e.to_string()),
        }
    }

    /// The exact refusal the runtime hands back (pinned by
    /// `no_peers_does_not_count_as_sent`): a Failed send carrying the
    /// no-peers text is the signal to re-drive the frame.
    #[test]
    fn the_no_peers_refusal_is_retryable() {
        let sent = send_result(
            MessageDeliveryStatus::Failed,
            Some("Moss error: no peers yet, so the message did not go out"),
        );
        assert!(refused_for_no_peers(&sent));
    }

    /// The probe works around exactly that refusal and nothing else. A send
    /// that moss accepted, or one that failed for a real transport fault, is
    /// not a retry.
    #[test]
    fn anything_else_is_not_retryable() {
        let accepted = send_result(MessageDeliveryStatus::Sent, None);
        assert!(!refused_for_no_peers(&accepted));

        let pending = send_result(MessageDeliveryStatus::Pending, None);
        assert!(!refused_for_no_peers(&pending));

        let fault = send_result(
            MessageDeliveryStatus::Failed,
            Some("Moss error: publish failed: -1"),
        );
        assert!(!refused_for_no_peers(&fault));

        let refused_text_no_status = send_result(
            MessageDeliveryStatus::Sent,
            Some("Moss error: no peers yet, so the message did not go out"),
        );
        assert!(!refused_for_no_peers(&refused_text_no_status));
    }

    /// The refusal text cannot drift away from the runtime's wording: this
    /// is the string `MossFfiError::NoPeers` renders and the channel runtime
    /// regression test pins (ADR 0021).
    #[test]
    fn the_no_peers_text_matches_the_runtime_display() {
        assert_eq!(
            NO_PEERS_TEXT,
            mosh_core::moss_ffi::MossFfiError::NoPeers.to_string()
        );
    }
}
