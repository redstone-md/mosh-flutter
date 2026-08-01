//! Org facade.
//!
//! Surfaces the former `org_*` Tauri command group: join, leave, list, poll,
//! DM-offer send/accept/dismiss, group create/accept-offer/dismiss-offer,
//! and group member invite. Poll maps to a `StreamSink`-returning facade
//! function, mirroring the former Tauri event that streamed org snapshots.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<OrgRuntime>>>`, the analogue of the Tauri shell's
//! `OrgState` (managed struct + `runtime: Mutex<Option<...>>` +
//! `load_error`). `ensure_runtime()` is the analogue of `OrgState::ready`
//! (construction) + `with_runtime` (lock + borrow). Each public function
//! calls `ensure_runtime()` and delegates, mapping `OrgError` to a plain
//! `String` so the bridge surfaces it as a Dart exception (ADR 0010).
//!
//! SHARED RESOURCES (ADR 0016 -- shared-runtime refactor): the Moss node +
//! persistence are borrowed from `api::shared_runtime` via
//! `ensure_shared_resources()`, exactly like the Tauri shell's
//! `OrgState::ready(shared_node, persistence)` which was handed the SAME
//! `Arc<SharedMossNode>` the DM/channel/group states got. No per-facade Moss
//! load. Orgs carry no attachments, so the attachment store is NOT borrowed.
//!
//! TYPES (ADR 0010 -- 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::org_runtime::{...}` and
//! (for the DM-offer commands, which in the Tauri shell also drove the
//! private-DM runtime to mint/accept the invite) the private-DM contracts.
//! They are NOT redefined. `Result<T, String>` matches the Tauri command
//! shape exactly; this facade maps `OrgError` to a plain `String` so the
//! bridge surfaces it as a Dart exception.
//!
//! CROSS-RUNTIME NOTE: the Tauri `org_send_dm_offer` / `org_accept_dm_offer`
//! and `org_create_group` / `org_accept_group_offer` commands touched TWO
//! managed states (`OrgState` + `PrivateDmState` or `PrivateGroupState`).
//! The api facade collapses both into one function per command (ADR 0010
//! 1:1 rule); the future impl drives both singletons from inside the one
//! function. The simple single-runtime bodies (join_org, poll, list,
//! dismiss_dm_offer, dismiss_group_offer) ARE implemented here; the
//! cross-runtime bodies (leave_org, send_dm_offer, accept_dm_offer,
//! create_group, accept_group_offer, group_invite_members) stay `todo!()`
//! -- they need access to the DM/group OnceLock singletons, a later atomic.

#![allow(unused_variables)]

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::org_runtime::{
    JoinOrgRequest, OrgDmOfferView, OrgError, OrgGroupOfferView, OrgRuntime, OrgSnapshot,
};
use crate::private_dm_runtime::{
    AcceptInviteRequest, InviteCreated, SessionSnapshot, StartSessionRequest,
};
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupSnapshot, JoinGroupRequest,
};

// Mirrors the Tauri shell's `ORG_UNAVAILABLE` constant so the error string
// is byte-identical across the old and new shells.
const ORG_UNAVAILABLE: &str = "org runtime unavailable";
const LOCK_POISONED: &str = "org runtime lock poisoned";

/// Process-global singleton for the org runtime (ADR 0016).
///
/// `Option` carries the same "ready vs missing" duality the Tauri shell's
/// `OrgState` did: `Some` once Moss loaded, `None` if construction failed (so
/// later calls report the original error instead of retrying into the same
/// failure). The `OnceLock` guarantees a single construction; the `Mutex`
/// serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<OrgRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call (the Tauri shell kept this in `OrgState::load_error`).
static LOAD_ERROR: OnceLock<String> = OnceLock::new();

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: borrow the shared resources (Moss node + persistence
/// via `api::shared_runtime`), build the org runtime off them, rehydrate
/// saved orgs from the encrypted store, and store it. On every later call:
/// just lock. Returns a guard the public functions can drive the `&mut self`
/// runtime through, or an error string matching the Tauri shell's
/// `unavailable_message` shape.
fn ensure_runtime() -> Result<MutexGuard<'static, Option<OrgRuntime>>, String> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex.lock().map_err(|_| LOCK_POISONED.to_string())?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{ORG_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| ORG_UNAVAILABLE.to_string());
        return Err(message);
    }
    Ok(guard)
}

/// Build the singleton value once. Returns `Some(runtime)` on success, or
/// `None` + caches the cause in `LOAD_ERROR` on failure. Split out from
/// `ensure_runtime` to keep that function's nesting shallow.
fn build_runtime() -> Option<OrgRuntime> {
    match construct_runtime() {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            let _ = LOAD_ERROR.set(error.to_string());
            None
        }
    }
}

/// The org-runtime construction recipe: borrow the shared resources (Moss
/// node + persistence) from `api::shared_runtime`, build an
/// `OrgRuntime::from_shared_node` off them, then rehydrate saved orgs from
/// the encrypted store. Mirrors the Tauri shell's `OrgState::ready`
/// (lib.rs L245-264) including the `rehydrate()` call.
fn construct_runtime() -> Result<OrgRuntime, OrgError> {
    let resources = crate::api::shared_runtime::ensure_shared_resources()
        .map_err(|error| OrgError::Moss(error))?;
    let mut runtime = OrgRuntime::from_shared_node(resources.shared_node, resources.persistence);
    // Rehydrate saved orgs from the encrypted store; with persistence wired
    // it now rebuilds joined orgs + their rosters instead of the slice-one
    // no-op. Matches the Tauri shell's `OrgState::ready` ordering (lib.rs
    // L256).
    runtime.rehydrate();
    Ok(runtime)
}

/// Join an org from a `mosh://org` bundle URI (1:1 port of `org_join`,
/// src-tauri/src/lib.rs L958-964). Delegates to `OrgRuntime::join_org`.
pub fn join_org(request: JoinOrgRequest) -> Result<OrgSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.join_org(request).map_err(|error| error.to_string())
}

/// Leave an org and close its bound groups (1:1 port of `org_leave`). The
/// Tauri command also closed the org's bound private groups; the future impl
/// drives both the org and group singletons from this one function.
//
// CROSS-RUNTIME (org + private_group): needs access to the PrivateGroup
// OnceLock singleton to call `close_org_groups`. Deferred to a later atomic
// that wires the cross-runtime access; the simple single-runtime bodies
// land first (this file's join_org/poll/list/dismiss_*).
pub fn leave_org(org_pubkey: String) -> Result<(), String> {
    // Drop the org from the org runtime; close its bound private groups so
    // they do not linger frozen (mirrors Tauri lib.rs L966-984). The group
    // runtime reconciles bound groups via close_org_groups; revocation
    // needs no extra wiring here (the group runtime reconciles against the
    // persisted roster on its own drain cadence).
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .leave_org(&org_pubkey)
            .map_err(|error| error.to_string())?;
    }
    {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.close_org_groups(&org_pubkey);
    }
    Ok(())
}

/// List all joined orgs and their snapshots (1:1 port of `org_list`,
/// src-tauri/src/lib.rs L985-989). The runtime's `list` returns a
/// `Vec<OrgSnapshot>` directly (no Result), so the facade wraps it in `Ok`
/// to match the Tauri command's `Result<Vec<OrgSnapshot>, String>` shape.
pub fn list() -> Result<Vec<OrgSnapshot>, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    Ok(runtime.list())
}

/// Poll an org for its current snapshot (1:1 port of `org_poll`,
/// src-tauri/src/lib.rs L992-995). Delegates to `OrgRuntime::poll`.
pub fn poll(org_pubkey: String) -> Result<OrgSnapshot, String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.poll(&org_pubkey).map_err(|error| error.to_string())
}

/// Send a private-DM invitation to one org member (1:1 port of
/// `org_send_dm_offer`). Mints the invite via the private-DM runtime and
/// records the offer in the org runtime; the future impl drives both.
//
// CROSS-RUNTIME (org + private_dm): mints the invite via the PrivateDm
// OnceLock singleton, then records + links in the org singleton. Deferred
// to a later atomic.
pub fn send_dm_offer(
    org_pubkey: String,
    target_peer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<InviteCreated, String> {
    // Mint the invite via the private-DM runtime, then record + link it in
    // the org runtime (mirrors Tauri lib.rs L997-1035). On an org-side failure
    // drop the orphan local invite so it does not linger as a dead "waiting"
    // session.
    let invite = {
        let mut guard = crate::api::private_dm::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .create_invite(StartSessionRequest {
                display_name,
                listen_port,
                static_peer,
            })
            .map_err(|error| error.to_string())?
    };
    let offered = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .send_dm_offer(&org_pubkey, &target_peer_id, &invite.invite_uri)
            .map_err(|error| error.to_string())?;
        runtime
            .link_dm(&org_pubkey, &target_peer_id, &invite.session_id)
            .map_err(|error| error.to_string())
    };
    if let Err(error) = offered {
        // The offer never reached the mesh: drop the orphan local invite.
        let mut guard = crate::api::private_dm::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        let _ = runtime.close_session(&invite.session_id);
        return Err(error);
    }
    Ok(invite)
}

/// Accept an org-carried DM offer (1:1 port of `org_accept_dm_offer`).
/// Accepts the invite via the private-DM runtime and clears the offer in the
/// org runtime; the future impl drives both.
//
// CROSS-RUNTIME (org + private_dm). Deferred to a later atomic.
pub fn accept_dm_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<SessionSnapshot, String> {
    // Accept the offer in the org runtime (returns the offer view with the
    // invite URI + the inviter peer id), then accept the invite via the
    // private-DM runtime, then link the resulting session in the org runtime
    // (mirrors Tauri lib.rs L1037-1068).
    let offer: OrgDmOfferView = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .accept_dm_offer(&org_pubkey, &offer_id)
            .map_err(|error| error.to_string())?
    };
    let snapshot = {
        let mut guard = crate::api::private_dm::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .accept_invite(AcceptInviteRequest {
                invite_uri: offer.invite_uri.clone(),
                display_name,
                listen_port,
                static_peer,
            })
            .map_err(|error| error.to_string())?
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .link_dm(&org_pubkey, &offer.from_peer_id, &snapshot.session_id)
            .map_err(|error| error.to_string())?
    }
    Ok(snapshot)
}

/// Dismiss an org DM offer (1:1 port of `org_dismiss_dm_offer`,
/// src-tauri/src/lib.rs L1070-1076). Delegates to
/// `OrgRuntime::dismiss_dm_offer`.
pub fn dismiss_dm_offer(org_pubkey: String, offer_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&org_pubkey, &offer_id)
        .map_err(|error| error.to_string())
}

/// Create an org-bound private group (1:1 port of `org_create_group`).
/// Creates the group via the private-group runtime and records the binding in
/// the org runtime; the future impl drives both.
//
// CROSS-RUNTIME (org + private_group). Deferred to a later atomic.
pub fn create_group(
    org_pubkey: String,
    label: Option<String>,
    member_peer_ids: Vec<String>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupCreated, String> {
    // Create the org-bound private group via the private-group runtime
    // (org_pubkey stamped on the CreateGroupRequest so the group carries its
    // roster binding), then offer it to each listed roster member via the org
    // runtime send_group_offer path (mirrors Tauri lib.rs L1093-1124).
    let created = {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .create_group(CreateGroupRequest {
                label: label.clone(),
                display_name,
                listen_port,
                static_peer,
                org_pubkey: Some(org_pubkey.clone()),
            })
            .map_err(|error| error.to_string())?
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        for target in &member_peer_ids {
            runtime
                .send_group_offer(
                    &org_pubkey,
                    target,
                    &created.invite_uri,
                    created.label.clone(),
                )
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(created)
}

/// Accept an org-carried group offer (1:1 port of `org_accept_group_offer`).
/// Joins the group via the private-group runtime and clears the offer in the
/// org runtime; the future impl drives both.
//
// CROSS-RUNTIME (org + private_group). Deferred to a later atomic.
pub fn accept_group_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupSnapshot, String> {
    // Accept the offer in the org runtime (returns the offer view with the
    // group invite URI), then join the group via the private-group runtime
    // (org_pubkey stamped on the JoinGroupRequest so the group carries its
    // roster binding) (mirrors Tauri lib.rs L1126-1152).
    let offer: OrgGroupOfferView = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .accept_group_offer(&org_pubkey, &offer_id)
            .map_err(|error| error.to_string())?
    };
    {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime
            .join_group(JoinGroupRequest {
                invite_uri: offer.group_invite_uri.clone(),
                display_name,
                org_pubkey: Some(org_pubkey.clone()),
                listen_port,
                static_peer,
            })
            .map_err(|error| error.to_string())
    }
}

/// Dismiss an org group offer (1:1 port of `org_dismiss_group_offer`,
/// src-tauri/src/lib.rs L1154-1162). Delegates to
/// `OrgRuntime::dismiss_group_offer`.
pub fn dismiss_group_offer(org_pubkey: String, offer_id: String) -> Result<(), String> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_group_offer(&org_pubkey, &offer_id)
        .map_err(|error| error.to_string())
}

/// One-click invite the roster members not yet in a group (1:1 port of
/// `org_group_invite_members`). Re-offers the group's invite URI to each
/// listed peer via the org runtime's group-offer path.
//
// CROSS-RUNTIME (org + private_group: needs the group's invite URI).
// Deferred to a later atomic.
pub fn group_invite_members(
    org_pubkey: String,
    group_id: String,
    member_peer_ids: Vec<String>,
) -> Result<(), String> {
    // The "+N roster members not in group" one-click add (spec §5): poll the
    // group for its invite URI + label, then re-offer the invite to each
    // listed roster member over org-control (mirrors Tauri lib.rs L1169-1192).
    let (invite_uri, label) = {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        let snapshot = runtime.poll(&group_id).map_err(|error| error.to_string())?;
        let uri = snapshot
            .invite_uri
            .ok_or_else(|| format!("group {group_id} has no invite URI"))?;
        (uri, snapshot.label)
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        for target in &member_peer_ids {
            runtime
                .send_group_offer(&org_pubkey, target, &invite_uri, label.clone())
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}
