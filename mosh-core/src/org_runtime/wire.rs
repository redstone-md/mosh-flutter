//! Room transport, signed org control messages and their wire formats.

use super::*;

/// Puts an org's room on the shared node and subscribes its control channel
/// there. Wire-identical to what a node owning that room published before, so a
/// consolidated client still talks to every already-released one.
pub(super) fn join_org_room(node: &MossNode, mesh_id: &str) -> Result<(), OrgError> {
    node.join_room(mesh_id)
        .map_err(|e| OrgError::Moss(e.to_string()))?;
    node.subscribe_room(mesh_id, &format!("{ORG_CONTROL_PREFIX}{mesh_id}"))
        .map_err(|e| OrgError::Moss(e.to_string()))
}

/// The inverse of `join_org_room`. Unsubscribe first, then forget the key:
/// leaving first would strand a subscription that can no longer resolve.
pub(super) fn leave_org_room(session: &OrgSession) {
    if let Err(error) = session
        .node
        .unsubscribe_room(&session.mesh_id, &session.control_channel)
    {
        dlog::write(
            LogLevel::Warn,
            kinds::ROOM,
            &session.org_pubkey,
            &format!("org could not unsubscribe its control channel: {error}"),
        );
    }
    if let Err(error) = session.node.leave_room(&session.mesh_id) {
        dlog::write(
            LogLevel::Warn,
            kinds::ROOM,
            &session.org_pubkey,
            &format!("org could not leave its room: {error}"),
        );
    }
}

pub(super) fn publish_signed(session: &OrgSession, message: &OrgMessage) -> Result<(), OrgError> {
    let payload = serde_json::to_vec(message).map_err(|e| OrgError::Codec(e.to_string()))?;
    let env = org_envelope::sign(&session.signer, &session.ctx(), &payload);
    let wire = OrgWire::Signed {
        payload_b64: encode(&env.payload),
        peer_id: env.peer_id,
        sig_b64: encode(&env.sig),
    };
    let bytes = serde_json::to_vec(&wire).map_err(|e| OrgError::Codec(e.to_string()))?;
    // Best-effort: an org control frame repeats on the roster cadence, so an
    // org whose mesh has not formed yet is not a failure to hand back.
    session
        .node
        .publish_room_best_effort(&session.mesh_id, &session.control_channel, &bytes)
        .map_err(|e| OrgError::Moss(e.to_string()))
}

pub(super) fn encode(bytes: &[u8]) -> String {
    base64::Engine::encode(&base64::engine::general_purpose::STANDARD, bytes)
}

pub(super) fn decode(encoded: &str) -> Result<Vec<u8>, OrgError> {
    base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|e| OrgError::Codec(e.to_string()))
}

pub(super) fn random_id() -> Result<String, OrgError> {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng
        .try_fill_bytes(&mut bytes)
        .map_err(|e| OrgError::Codec(e.to_string()))?;
    Ok(hex::encode(bytes))
}

pub(super) fn upsert_link(links: &mut Vec<OrgDmLink>, peer_id: &str, session_id: Option<String>) {
    if let Some(link) = links.iter_mut().find(|link| link.peer_id == peer_id) {
        // Never downgrade a known session id back to None on a re-offer.
        if session_id.is_some() {
            link.session_id = session_id;
        }
        return;
    }
    links.push(OrgDmLink {
        peer_id: peer_id.to_string(),
        session_id,
    });
}

/// Roster bytes authenticate themselves; other messages require OrgSigned.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub(super) enum OrgWire {
    Roster {
        roster_b64: String,
    },
    Signed {
        payload_b64: String,
        peer_id: String,
        sig_b64: String,
    },
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub(super) enum OrgMessage {
    Hello {
        moss_peer_id: String,
        display_name: String,
    },
    /// Roster-driven DM bootstrap (spec §4): carries a regular DM invite URI
    /// so both sides land in the existing create/accept machinery. Accepted
    /// only from verified roster members, accept-once by `offer_id`.
    DmOffer {
        offer_id: String,
        target_peer_id: String,
        from_name: String,
        invite_uri: String,
    },
    /// Invitation into an org-bound group (spec §5): only roster members
    /// receive offers; the invite URI feeds the normal group join flow.
    GroupOffer {
        offer_id: String,
        target_peer_id: String,
        from_name: String,
        group_label: Option<String>,
        group_invite_uri: String,
    },
}

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PersistedOrgRecord {
    pub(crate) org_pubkey: String,
    pub(crate) org_name: String,
    pub(crate) mesh_id: String,
    pub(crate) display_name: String,
    pub(crate) listen_port: u16,
    pub(crate) static_peer: Option<String>,
    #[serde(default)]
    pub(crate) dm_links: Vec<OrgDmLink>,
    /// Dismissed offers and acceptances whose native conversation is durable.
    #[serde(default)]
    pub(crate) resolved_offer_ids: std::collections::BTreeSet<String>,
    #[serde(default)]
    pub(crate) pending_acceptances: std::collections::BTreeMap<String, PendingAcceptance>,
}
