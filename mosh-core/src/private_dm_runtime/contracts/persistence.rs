//! Encrypted DM session record and bounded read-receipt history.

use super::*;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedSession {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) invitation: Option<crate::private_dm_runtime::invitations::InviteLifecycle>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) membership: Option<crate::private_dm_runtime::devices::DeviceMembership>,
    pub role_is_alice: bool,
    pub display_name: String,
    pub participant_id: String,
    pub session_id: String,
    pub mesh_id: String,
    pub fingerprint: String,
    pub invite_uri: Option<String>,
    pub signer_public: Vec<u8>,
    pub group_id: Vec<u8>,
    pub listen_port: u16,
    pub static_peer: Option<String>,
    /// The counterpart's moss peer id, learned from its KeyPackage/Welcome.
    /// Persisted because it is the ONLY thing separating our peer from the
    /// unrelated world peers on the shared substrate: a restored session
    /// without it cannot tell whether the counterpart is online, cannot dial
    /// it, and cannot address a relayed send. Defaulted so records written
    /// before this field existed still load.
    #[serde(default)]
    pub peer_moss_id: Option<String>,
    /// Message ids the counterpart has authenticated a read of, persisted so
    /// a restart does not re-ask (a re-asked receipt is a frame the peer has
    /// to answer again for something it already told us). Defaulted so
    /// records written before this field existed still load. Pruned to the
    /// last `READ_HISTORY_KEEP` ids on write, so the record cannot grow
    /// without bound.
    #[serde(default)]
    pub read_message_ids: Vec<String>,
}

/// How many read ids a session record keeps (the same bound the runtime
/// applies in memory; re-declared here so the serialized shape's contract
/// lives beside the field).
pub const READ_HISTORY_KEEP: usize = 512;

/// Keeps the LAST ids (the newest reads) and drops the rest, once the list
/// outgrows the cap. Order is preserved for the ids that stay.
pub fn prune_read_ids(ids: &[String]) -> Vec<String> {
    let overflow = ids.len().saturating_sub(READ_HISTORY_KEEP);
    ids.iter().skip(overflow).cloned().collect()
}
