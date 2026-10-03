//! Organization runtime (spec §3): each joined org is a room on the process's
//! one moss node, roster gossip on `org-control/<mesh_id>`, and the member side
//! of the join flow. The org itself is a signed document, not a server — this
//! runtime only verifies and reacts; all authority lives in the roster
//! signature.

use std::collections::HashMap;
use std::sync::Arc;

use ed25519_dalek::SigningKey;
use serde::{Deserialize, Serialize};

use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::inbox;
use crate::moss_ffi::{MossFfiRuntime, MossNode};
use crate::org_envelope::{self, OrgContext, OrgSigned};
use crate::org_roster::{self, Roster, RosterError};
use crate::org_signing;
use crate::persistence::Persistence;
use crate::shared_node::SharedMossNode;

const ORG_CONTROL_PREFIX: &str = "org-control/";

/// The org's own inbound queue, claimed once for the process.
fn org_inbox() -> &'static inbox::Inbox {
    static INBOX: std::sync::OnceLock<inbox::Inbox> = std::sync::OnceLock::new();
    INBOX.get_or_init(|| inbox::register(|channel| channel.starts_with(ORG_CONTROL_PREFIX)))
}
const ORG_CHANNEL_KIND: &str = "org-control";
const ORG_BUNDLE_PREFIX: &str = "mosh://org";

#[derive(Debug, Clone, Deserialize)]
pub struct JoinOrgRequest {
    pub bundle_uri: String,
    pub display_name: String,
    pub listen_port: u16,
    pub static_peer: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrgMemberView {
    pub moss_peer_id: String,
    pub name: String,
    pub role: String,
    pub is_self: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrgDmOfferView {
    pub offer_id: String,
    pub from_peer_id: String,
    pub from_name: String,
    pub invite_uri: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrgDmLink {
    pub peer_id: String,
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrgGroupOfferView {
    pub offer_id: String,
    pub from_peer_id: String,
    pub from_name: String,
    pub group_label: Option<String>,
    pub group_invite_uri: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrgSnapshot {
    pub org_pubkey: String,
    pub org_name: String,
    pub mesh_id: String,
    pub own_peer_id: String,
    pub confirmation_code: String,
    pub in_roster: bool,
    pub roster_version: Option<u64>,
    pub members: Vec<OrgMemberView>,
    pub dm_offers: Vec<OrgDmOfferView>,
    pub group_offers: Vec<OrgGroupOfferView>,
    pub dm_links: Vec<OrgDmLink>,
}

#[derive(Debug)]
pub enum OrgError {
    InvalidBundle(String),
    Duplicate(String),
    NotJoined(String),
    IdentityUnavailable,
    Moss(String),
    Persistence(String),
    Codec(String),
}

impl std::fmt::Display for OrgError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidBundle(why) => write!(f, "invalid org bundle: {why}"),
            Self::Duplicate(org) => write!(f, "already joined org {org}"),
            Self::NotJoined(org) => write!(f, "not joined to org {org}"),
            Self::IdentityUnavailable => {
                write!(f, "moss identity unavailable; cannot sign org messages")
            }
            Self::Moss(e) => write!(f, "moss error: {e}"),
            Self::Persistence(e) => write!(f, "persistence error: {e}"),
            Self::Codec(e) => write!(f, "codec error: {e}"),
        }
    }
}

impl std::error::Error for OrgError {}

/// `mosh://org?mesh=<org_mesh_id>&name=<label>#org=<org_pubkey_64hex>`.
/// The fragment carries the trust anchor, the query only routing — same
/// split as DM invites, so a logged/leaked URL without its fragment does
/// not identify the org key.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedOrgBundle {
    pub org_pubkey: String,
    pub org_name: String,
    pub mesh_id: String,
}

impl ParsedOrgBundle {
    pub fn parse(uri: &str) -> Result<Self, OrgError> {
        if !uri.starts_with(ORG_BUNDLE_PREFIX) {
            return Err(OrgError::InvalidBundle("not a mosh://org URI".into()));
        }
        let url =
            url::Url::parse(uri).map_err(|e| OrgError::InvalidBundle(format!("parse: {e}")))?;
        let mesh_id = query(&url, "mesh")?;
        let org_name = query(&url, "name")?;
        let fragment = url
            .fragment()
            .ok_or_else(|| OrgError::InvalidBundle("missing #org fragment".into()))?;
        let org_pubkey = fragment
            .strip_prefix("org=")
            .ok_or_else(|| OrgError::InvalidBundle("fragment is not org=<pubkey>".into()))?
            .to_ascii_lowercase();
        if org_pubkey.len() != 64 || !org_pubkey.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(OrgError::InvalidBundle(
                "org pubkey must be 64 hex chars".into(),
            ));
        }
        Ok(Self {
            org_pubkey,
            org_name,
            mesh_id,
        })
    }
}

pub(super) fn query(url: &url::Url, key: &str) -> Result<String, OrgError> {
    url.query_pairs()
        .find(|(candidate, _)| candidate == key)
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| OrgError::InvalidBundle(format!("missing {key}")))
}

struct OrgSession {
    org_pubkey: String,
    org_name: String,
    mesh_id: String,
    display_name: String,
    listen_port: u16,
    static_peer: Option<String>,
    node: Arc<MossNode>,
    control_channel: String,
    signer: SigningKey,
    own_peer_id: String,
    roster: Option<Roster>,
    /// The exact verified bytes behind `roster` — republished verbatim so
    /// the org signature stays valid (re-serializing could reorder fields).
    roster_bytes: Option<Vec<u8>>,
    dm_offers: Vec<OrgDmOfferView>,
    group_offers: Vec<OrgGroupOfferView>,
    dm_links: Vec<OrgDmLink>,
    seen_offer_ids: std::collections::HashSet<String>,
    #[cfg(test)]
    roster_publishes: u32,
}

pub struct OrgRuntime {
    // The one moss node this process runs. Every joined org is a room on it,
    // not a node of its own — see `shared_node` for why more than one is
    // actively harmful.
    shared_node: Arc<SharedMossNode>,
    persistence: Option<Arc<Persistence>>,
    orgs: HashMap<String, OrgSession>,
}

impl OrgRuntime {
    fn session_mut(&mut self, key: &str) -> Result<&mut OrgSession, OrgError> {
        self.orgs
            .get_mut(key)
            .ok_or_else(|| OrgError::NotJoined(key.to_string()))
    }

    pub fn from_shared(moss: Arc<MossFfiRuntime>, persistence: Option<Arc<Persistence>>) -> Self {
        Self::from_shared_node(SharedMossNode::new(moss), persistence)
    }

    /// The constructor a real client uses: every runtime in the process is
    /// handed the SAME holder, so orgs share their node with DMs, channels and
    /// groups. `from_shared` mints a private holder, which is what tests
    /// running two peers in one process need.
    pub fn from_shared_node(
        shared_node: Arc<SharedMossNode>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        // Claim the org control channels before any node of ours can start;
        // see `crate::inbox`.
        org_inbox();
        Self {
            shared_node,
            persistence,
            orgs: HashMap::new(),
        }
    }

    pub fn join_org(&mut self, request: JoinOrgRequest) -> Result<OrgSnapshot, OrgError> {
        let bundle = ParsedOrgBundle::parse(&request.bundle_uri)?;
        if self.orgs.contains_key(&bundle.org_pubkey) {
            return Err(OrgError::Duplicate(bundle.org_pubkey));
        }
        let node =
            self.open_org_room(&bundle.mesh_id, request.listen_port, &request.static_peer)?;
        // Read AFTER node start: on a truly fresh install the keystore only
        // receives the identity when the first node comes up.
        let signer = self.signing_key()?;
        let record = PersistedOrgRecord {
            org_pubkey: bundle.org_pubkey.clone(),
            org_name: bundle.org_name.clone(),
            mesh_id: bundle.mesh_id.clone(),
            display_name: request.display_name.clone(),
            listen_port: request.listen_port,
            static_peer: request.static_peer.clone(),
            dm_links: Vec::new(),
        };
        self.persist_record(&record)?;
        let session = self.build_session(record, node, signer);
        session.publish_hello();
        let snapshot = session.snapshot();
        self.orgs.insert(session.org_pubkey.clone(), session);
        Ok(snapshot)
    }

    pub fn leave_org(&mut self, org_pubkey: &str) -> Result<(), OrgError> {
        let session = self
            .orgs
            .remove(org_pubkey)
            .ok_or_else(|| OrgError::NotJoined(org_pubkey.to_string()))?;
        // On a shared node dropping the session no longer ends its
        // subscription — the node lives on for the other orgs, so leaving has
        // to be said out loud or a left org keeps receiving roster gossip.
        leave_org_room(&session);
        self.shared_node.release();
        if let Some(p) = self.persistence.as_ref() {
            p.delete_org(org_pubkey)
                .map_err(|e| OrgError::Persistence(e.to_string()))?;
        }
        Ok(())
    }

    pub fn poll(&mut self, org_pubkey: &str) -> Result<OrgSnapshot, OrgError> {
        self.drain_inbound();
        let session = self
            .orgs
            .get_mut(org_pubkey)
            .ok_or_else(|| OrgError::NotJoined(org_pubkey.to_string()))?;
        if !session.in_roster() {
            session.publish_hello();
        }
        Ok(session.snapshot())
    }

    pub fn list(&mut self) -> Vec<OrgSnapshot> {
        self.drain_inbound();
        let mut out: Vec<OrgSnapshot> = self.orgs.values().map(OrgSession::snapshot).collect();
        out.sort_by(|a, b| a.org_name.cmp(&b.org_name));
        out
    }

    fn drain_inbound(&mut self) {
        let inbound = org_inbox().drain();
        for message in inbound {
            let persistence = self.persistence.clone();
            if let Some(session) = self
                .orgs
                .values_mut()
                .find(|s| s.control_channel == message.channel)
            {
                session.ingest_payload(persistence.as_deref(), &message.payload);
            }
        }
    }

    /// Deterministic inbound injection for tests — same code path as
    /// `drain_inbound` without depending on gossip delivery timing.
    #[cfg(test)]
    fn ingest_for_test(&mut self, org_pubkey: &str, payload: &[u8]) {
        let persistence = self.persistence.clone();
        if let Some(session) = self.orgs.get_mut(org_pubkey) {
            session.ingest_payload(persistence.as_deref(), payload);
        }
    }

    /// Take a reference to the shared node and put this org's room on it.
    /// Rolls the reference back if the room work fails, so an org that never
    /// joined cannot pin the node up forever.
    fn open_org_room(
        &self,
        mesh_id: &str,
        listen_port: u16,
        static_peer: &Option<String>,
    ) -> Result<Arc<MossNode>, OrgError> {
        let node = self
            .shared_node
            .acquire(listen_port, static_peer.clone())
            .map_err(|e| OrgError::Moss(e.to_string()))?;
        if let Err(error) = join_org_room(&node, mesh_id) {
            self.shared_node.release();
            return Err(error);
        }
        Ok(node)
    }
}

#[cfg(test)]
#[path = "org_runtime_tests.rs"]
mod tests;

use wire::*;

mod actions;
mod session;
mod storage;
mod wire;
