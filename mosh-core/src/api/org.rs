//! Org facade.
//!
//! Surfaces the `org_*` command group: join, leave, list, poll,
//! DM-offer send/accept/dismiss, group create/accept-offer/dismiss-offer,
//! and group member invite. Poll maps to a `StreamSink`-returning facade
//! function that streams org snapshots.
//!
//! OWNERSHIP (ADR 0016 -- api runtime ownership, OnceLock singleton): the
//! runtime is held in a process-global
//! `OnceLock<Mutex<Option<OrgRuntime>>>` plus a cached `load_error`.
//! `ensure_runtime()` constructs the singleton on first call, then locks
//! and borrows it. Each public function
//! calls `ensure_runtime()` and delegates. The actions return the typed
//! `ConversationBridgeError` (ADR 0024) through `From<OrgError>`; `list`
//! and `poll` keep the plain `String` shape (ADR 0010).
//!
//! SHARED RESOURCES (ADR 0016 -- shared-runtime refactor): the Moss node +
//! persistence are borrowed from `api::shared_runtime` via
//! `ensure_shared_resources()`: the same `Arc<SharedMossNode>` the
//! DM/channel/group facades get. No per-facade Moss
//! load. Orgs carry no attachments, so the attachment store is NOT borrowed.
//!
//! TYPES (ADR 0010 -- 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::org_runtime::{...}` and
//! (for the DM-offer commands, which also drive the private-DM runtime to
//! mint/accept the invite) the private-DM contracts.
//! They are NOT redefined.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::api::conversation_bridge::{ConversationBridgeError, ConversationBridgeErrorKind};
use crate::org_runtime::{
    JoinOrgRequest, OrgDmOfferView, OrgError, OrgGroupOfferView, OrgRuntime, OrgSnapshot,
};
use crate::private_dm_runtime::{
    AcceptInviteRequest, InviteCreated, SessionSnapshot, StartSessionRequest,
};
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupSnapshot, JoinGroupRequest,
};

const ORG_UNAVAILABLE: &str = "org runtime unavailable";
const LOCK_POISONED: &str = "org runtime lock poisoned";
// Every created or joined group stores its invite URI, so a group without
// one is a state the runtime never produces: no caller-visible remedy.
const GROUP_WITHOUT_INVITE: &str = "group has no invite URI";

/// Process-global singleton for the org runtime (ADR 0016).
///
/// `Option` carries the "ready vs missing" duality: `Some` once Moss
/// loaded, `None` if construction failed (so
/// later calls report the original error instead of retrying into the same
/// failure). The `OnceLock` guarantees a single construction; the `Mutex`
/// serializes the `&mut self` runtime calls.
static RUNTIME: OnceLock<Mutex<Option<OrgRuntime>>> = OnceLock::new();

/// The cached construction error, if the singleton's first init failed.
/// Lives in its own `OnceLock` so a failed init reports a stable message on
/// every later call.
static LOAD_ERROR: OnceLock<String> = OnceLock::new();

/// Lazily construct the singleton on first call, then lock it.
///
/// On the first call: borrow the shared resources (Moss node + persistence
/// via `api::shared_runtime`), build the org runtime off them, rehydrate
/// saved orgs from the encrypted store, and store it. On every later call:
/// just lock. Returns a guard the public functions can drive the `&mut self`
/// runtime through, or an `Unavailable` bridge error.
fn ensure_runtime() -> Result<MutexGuard<'static, Option<OrgRuntime>>, ConversationBridgeError> {
    let mutex = RUNTIME.get_or_init(|| Mutex::new(build_runtime()));
    let guard = mutex
        .lock()
        .map_err(|_| ConversationBridgeError::unavailable(LOCK_POISONED))?;
    if guard.is_none() {
        // Construction failed on the first call; the cause is cached.
        let message = LOAD_ERROR
            .get()
            .map(|error| format!("{ORG_UNAVAILABLE}: {error}"))
            .unwrap_or_else(|| ORG_UNAVAILABLE.to_string());
        return Err(ConversationBridgeError::unavailable(message));
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
/// the encrypted store.
fn construct_runtime() -> Result<OrgRuntime, OrgError> {
    let resources =
        crate::api::shared_runtime::ensure_shared_resources().map_err(OrgError::Moss)?;
    let mut runtime = OrgRuntime::from_shared_node(resources.shared_node, resources.persistence);
    // Rehydrate saved orgs from the encrypted store; with persistence wired
    // it rebuilds joined orgs + their rosters.
    runtime.rehydrate();
    Ok(runtime)
}

/// Join an org from a `mosh://org` bundle URI. Delegates to `OrgRuntime::join_org`.
pub fn join_org(request: JoinOrgRequest) -> Result<OrgSnapshot, ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .join_org(request)
        .map_err(ConversationBridgeError::from)
}

/// Leave an org and close its bound groups. This function
/// drives both the org and group singletons from one place.
pub fn leave_org(org_pubkey: String) -> Result<(), ConversationBridgeError> {
    // Drop the org from the org runtime; close its bound private groups so
    // they do not linger frozen. The group
    // runtime reconciles bound groups via close_org_groups; revocation
    // needs no extra wiring here (the group runtime reconciles against the
    // persisted roster on its own drain cadence).
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.leave_org(&org_pubkey)?;
    }
    {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.close_org_groups(&org_pubkey);
    }
    Ok(())
}

/// List all joined orgs and their snapshots. The runtime's `list` returns a
/// `Vec<OrgSnapshot>` directly (no Result), so the facade wraps it in `Ok`
/// for the bridge's `Result<Vec<OrgSnapshot>, String>` shape.
pub fn list() -> Result<Vec<OrgSnapshot>, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    Ok(runtime.list())
}

/// Poll an org for its current snapshot. Delegates to `OrgRuntime::poll`.
pub fn poll(org_pubkey: String) -> Result<OrgSnapshot, String> {
    let mut guard = ensure_runtime().map_err(|error| error.to_string())?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime.poll(&org_pubkey).map_err(|error| error.to_string())
}

/// Send a private-DM invitation to one org member. Mints the invite via
/// the private-DM runtime and
/// records the offer in the org runtime.
pub fn send_dm_offer(
    org_pubkey: String,
    target_peer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<InviteCreated, ConversationBridgeError> {
    // Mint the invite via the private-DM runtime, then record + link it in
    // the org runtime. On an org-side failure
    // drop the orphan local invite so it does not linger as a dead "waiting"
    // session.
    let invite = {
        let mut guard = crate::api::private_dm::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.create_invite(StartSessionRequest {
            display_name,
            listen_port,
            static_peer,
        })?
    };
    let offered = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.send_dm_offer(&org_pubkey, &target_peer_id, &invite.invite_uri)?;
        runtime
            .link_dm(&org_pubkey, &target_peer_id, &invite.session_id)
            .map_err(ConversationBridgeError::from)
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

/// Accept an org-carried DM offer.
/// Accepts the invite via the private-DM runtime and clears the offer in the
/// org runtime.
pub fn accept_dm_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<SessionSnapshot, ConversationBridgeError> {
    // Accept the offer in the org runtime (returns the offer view with the
    // invite URI + the inviter peer id), then accept the invite via the
    // private-DM runtime, then link the resulting session in the org runtime.
    let offer: OrgDmOfferView = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.accept_dm_offer(&org_pubkey, &offer_id)?
    };
    let snapshot = {
        let mut guard = crate::api::private_dm::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.accept_invite(AcceptInviteRequest {
            invite_uri: offer.invite_uri.clone(),
            display_name,
            listen_port,
            static_peer,
        })?
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.link_dm(&org_pubkey, &offer.from_peer_id, &snapshot.session_id)?
    }
    Ok(snapshot)
}

/// Dismiss an org DM offer. Delegates to
/// `OrgRuntime::dismiss_dm_offer`.
pub fn dismiss_dm_offer(
    org_pubkey: String,
    offer_id: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_dm_offer(&org_pubkey, &offer_id)
        .map_err(ConversationBridgeError::from)
}

/// Create an org-bound private group.
/// Creates the group via the private-group runtime and records the binding in
/// the org runtime.
pub fn create_group(
    org_pubkey: String,
    label: Option<String>,
    member_peer_ids: Vec<String>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupCreated, ConversationBridgeError> {
    // Create the org-bound private group via the private-group runtime
    // (org_pubkey stamped on the CreateGroupRequest so the group carries its
    // roster binding), then offer it to each listed roster member via the org
    // runtime send_group_offer path.
    let created = {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.create_group(CreateGroupRequest {
            label: label.clone(),
            display_name,
            listen_port,
            static_peer,
            org_pubkey: Some(org_pubkey.clone()),
        })?
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        for target in &member_peer_ids {
            runtime.send_group_offer(
                &org_pubkey,
                target,
                &created.invite_uri,
                created.label.clone(),
            )?;
        }
    }
    Ok(created)
}

/// Accept an org-carried group offer.
/// Joins the group via the private-group runtime and clears the offer in the
/// org runtime.
pub fn accept_group_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupSnapshot, ConversationBridgeError> {
    // Accept the offer in the org runtime (returns the offer view with the
    // group invite URI), then join the group via the private-group runtime
    // (org_pubkey stamped on the JoinGroupRequest so the group carries its
    // roster binding).
    let offer: OrgGroupOfferView = {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        runtime.accept_group_offer(&org_pubkey, &offer_id)?
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
            .map_err(ConversationBridgeError::from)
    }
}

/// Dismiss an org group offer. Delegates to
/// `OrgRuntime::dismiss_group_offer`.
pub fn dismiss_group_offer(
    org_pubkey: String,
    offer_id: String,
) -> Result<(), ConversationBridgeError> {
    let mut guard = ensure_runtime()?;
    let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
    runtime
        .dismiss_group_offer(&org_pubkey, &offer_id)
        .map_err(ConversationBridgeError::from)
}

/// One-click invite the roster members not yet in a group. Re-offers the group's invite URI to each
/// listed peer via the org runtime's group-offer path.
pub fn group_invite_members(
    org_pubkey: String,
    group_id: String,
    member_peer_ids: Vec<String>,
) -> Result<(), ConversationBridgeError> {
    // The "+N roster members not in group" one-click add (spec §5): poll the
    // group for its invite URI + label, then re-offer the invite to each
    // listed roster member over org-control.
    let (invite_uri, label) = {
        let mut guard = crate::api::private_group::ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        let snapshot = runtime.poll(&group_id)?;
        let uri = snapshot.invite_uri.ok_or_else(|| {
            ConversationBridgeError::new(
                ConversationBridgeErrorKind::Internal,
                format!("{GROUP_WITHOUT_INVITE}: {group_id}"),
            )
        })?;
        (uri, snapshot.label)
    };
    {
        let mut guard = ensure_runtime()?;
        let runtime = guard.as_mut().expect("ensure_runtime guarantees Some");
        for target in &member_peer_ids {
            runtime.send_group_offer(&org_pubkey, target, &invite_uri, label.clone())?;
        }
    }
    Ok(())
}
