//! Org facade.
//!
//! Surfaces the former `org_*` Tauri command group: join, leave, list, poll,
//! DM-offer send/accept/dismiss, group create/accept-offer/dismiss-offer,
//! and group member invite. Poll maps to a `StreamSink`-returning facade
//! function, mirroring the former Tauri event that streamed org snapshots.
//!
//! Stub: signatures laid for the slice-one boundary; bodies `todo!()` —
//! implemented in a later slice (S2: ADR 0016 OnceLock singleton for the org
//! runtime family, bound through the bridge). No `OnceLock` /
//! `ensure_runtime` here yet — these stubs compile only and carry no
//! runtime behavior, so the bridge can be generated against the full org
//! command surface before the wiring lands.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::org_runtime::{...}` and
//! (for the DM-offer commands, which in the Tauri shell also drove the
//! private-DM runtime to mint/accept the invite) the private-DM contracts.
//! They are NOT redefined. `Result<T, String>` matches the Tauri command
//! shape exactly; the future implementation maps `OrgError` to a plain
//! `String` so the bridge surfaces it as a Dart exception.
//!
//! CROSS-RUNTIME NOTE: the Tauri `org_send_dm_offer` / `org_accept_dm_offer`
//! and `org_create_group` / `org_accept_group_offer` commands touched TWO
//! managed states (`OrgState` + `PrivateDmState` or `PrivateGroupState`).
//! The api facade collapses both into one function per command (ADR 0010
//! 1:1 rule); the future impl drives both singletons from inside the one
//! function. The signature below mirrors the Tauri parameter list verbatim,
//! so the bridge stays parameter-light and the cross-runtime wiring is an
//! implementation detail, not a surface change.

use crate::org_runtime::{JoinOrgRequest, OrgDmOfferView, OrgGroupOfferView, OrgSnapshot};
use crate::private_dm_runtime::{InviteCreated, SessionSnapshot};
use crate::private_group_runtime::{GroupCreated, GroupSnapshot};

/// Join an org from a `mosh://org` bundle URI (1:1 port of `org_join`).
pub fn join_org(request: JoinOrgRequest) -> Result<OrgSnapshot, String> {
    todo!("slice-2: implement org_join")
}

/// Leave an org and close its bound groups (1:1 port of `org_leave`). The
/// Tauri command also closed the org's bound private groups; the future impl
/// drives both the org and group singletons from this one function.
pub fn leave_org(org_pubkey: String) -> Result<(), String> {
    todo!("slice-2: implement org_leave")
}

/// List all joined orgs and their snapshots (1:1 port of `org_list`). The
/// runtime's `list` returns a `Vec<OrgSnapshot>` directly (no Result), so the
/// facade returns `Result<Vec<OrgSnapshot>, String>` to match the Tauri
/// command's `Result<Vec<OrgSnapshot>, String>` shape.
pub fn list() -> Result<Vec<OrgSnapshot>, String> {
    todo!("slice-2: implement org_list")
}

/// Poll an org for its current snapshot (1:1 port of `org_poll`).
pub fn poll(org_pubkey: String) -> Result<OrgSnapshot, String> {
    todo!("slice-2: implement org_poll")
}

/// Send a private-DM invitation to one org member (1:1 port of
/// `org_send_dm_offer`). Mints the invite via the private-DM runtime and
/// records the offer in the org runtime; the future impl drives both.
pub fn send_dm_offer(
    org_pubkey: String,
    target_peer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<InviteCreated, String> {
    todo!("slice-2: implement org_send_dm_offer")
}

/// Accept an org-carried DM offer (1:1 port of `org_accept_dm_offer`).
/// Accepts the invite via the private-DM runtime and clears the offer in the
/// org runtime; the future impl drives both.
pub fn accept_dm_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<SessionSnapshot, String> {
    todo!("slice-2: implement org_accept_dm_offer")
}

/// Dismiss an org DM offer (1:1 port of `org_dismiss_dm_offer`).
pub fn dismiss_dm_offer(org_pubkey: String, offer_id: String) -> Result<(), String> {
    todo!("slice-2: implement org_dismiss_dm_offer")
}

/// Create an org-bound private group (1:1 port of `org_create_group`).
/// Creates the group via the private-group runtime and records the binding in
/// the org runtime; the future impl drives both.
pub fn create_group(
    org_pubkey: String,
    label: Option<String>,
    member_peer_ids: Vec<String>,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupCreated, String> {
    todo!("slice-2: implement org_create_group")
}

/// Accept an org-carried group offer (1:1 port of `org_accept_group_offer`).
/// Joins the group via the private-group runtime and clears the offer in the
/// org runtime; the future impl drives both.
pub fn accept_group_offer(
    org_pubkey: String,
    offer_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<GroupSnapshot, String> {
    todo!("slice-2: implement org_accept_group_offer")
}

/// Dismiss an org group offer (1:1 port of `org_dismiss_group_offer`).
pub fn dismiss_group_offer(org_pubkey: String, offer_id: String) -> Result<(), String> {
    todo!("slice-2: implement org_dismiss_group_offer")
}

/// One-click invite the roster members not yet in a group (1:1 port of
/// `org_group_invite_members`). Re-offers the group's invite URI to each
/// listed peer via the org runtime's group-offer path.
pub fn group_invite_members(
    org_pubkey: String,
    group_id: String,
    member_peer_ids: Vec<String>,
) -> Result<(), String> {
    todo!("slice-2: implement org_group_invite_members")
}
