use redb::TableDefinition;

pub(super) const MLS_SNAPSHOT: TableDefinition<&str, &[u8]> = TableDefinition::new("mls_snapshot");
pub(super) const MESSAGES: TableDefinition<&str, &[u8]> = TableDefinition::new("messages");
pub(super) const SESSIONS: TableDefinition<&str, &[u8]> = TableDefinition::new("sessions");
pub(super) const GROUP_MLS_SNAPSHOT: TableDefinition<&str, &[u8]> =
    TableDefinition::new("group_mls_snapshot");
pub(super) const GROUP_MESSAGES: TableDefinition<&str, &[u8]> =
    TableDefinition::new("group_messages");
pub(super) const GROUPS: TableDefinition<&str, &[u8]> = TableDefinition::new("groups");
pub(super) const CHANNEL_MESSAGES: TableDefinition<&str, &[u8]> =
    TableDefinition::new("channel_messages");
pub(super) const CHANNELS: TableDefinition<&str, &[u8]> = TableDefinition::new("channels");
pub(super) const OUTBOUND_ATTEMPTS: TableDefinition<&str, &[u8]> =
    TableDefinition::new("outbound_attempts");
pub(super) const MOSS_IDENTITY: TableDefinition<&str, &[u8]> =
    TableDefinition::new("moss_identity");
// Single-row table: the device's stable Moss transport identity (libp2p key).
pub(super) const MOSS_IDENTITY_KEY: &str = "node-identity-v1";
pub(super) const DEVICE_LINK: TableDefinition<&str, &[u8]> = TableDefinition::new("device_link");
pub(super) const DEVICE_LINK_KEY: &str = "local-device-v1";
pub(super) const CHAT_NAMES: Rows = TableDefinition::new("chat_names");
pub(super) const MESSAGE_DELETIONS: Rows = TableDefinition::new("message_deletions");
pub(super) const ATTACHMENT_GC: Rows = TableDefinition::new("attachment_gc");
pub(super) const DELETION_ADMINS: Rows = TableDefinition::new("deletion_admins");
// Key: org pubkey hex -> latest verified roster bytes (multi-org).
pub(super) const ORG_ROSTERS: TableDefinition<&str, &[u8]> = TableDefinition::new("org_rosters");
// Key: "<group_id>/<epoch:020>" — zero-padded so lexicographic order == numeric.
pub(super) const GROUP_COMMIT_LOG: TableDefinition<&str, &[u8]> =
    TableDefinition::new("group_commit_log");
// Key: org pubkey hex -> serialized PersistedOrgRecord (bundle + node config).
pub(super) const ORG_RECORDS: TableDefinition<&str, &[u8]> = TableDefinition::new("org_records");

/// A table of encrypted rows keyed by a string.
pub(super) type Rows = TableDefinition<'static, &'static str, &'static [u8]>;

/// The existing encrypted tables and outbound scope for one conversation kind.
#[derive(Clone, Copy)]
pub struct HistoryTables {
    /// One row per conversation: the record it is rebuilt from at startup.
    pub(super) conversations: Rows,
    pub(super) snapshots: Option<Rows>,
    /// One row per message, keyed by conversation, send time and message id.
    pub(super) messages: Rows,
    /// The key prefix this kind's outbound attempts share.
    pub outbound_scope: &'static str,
    /// What one conversation is called in a warning about an unreadable row.
    pub label: &'static str,
}

pub const DM_HISTORY: HistoryTables = HistoryTables {
    conversations: SESSIONS,
    snapshots: Some(MLS_SNAPSHOT),
    messages: MESSAGES,
    outbound_scope: "private_dm",
    label: "session",
};

pub const GROUP_HISTORY: HistoryTables = HistoryTables {
    conversations: GROUPS,
    snapshots: Some(GROUP_MLS_SNAPSHOT),
    messages: GROUP_MESSAGES,
    outbound_scope: "private_group",
    label: "group",
};

pub const CHANNEL_HISTORY: HistoryTables = HistoryTables {
    conversations: CHANNELS,
    snapshots: None,
    messages: CHANNEL_MESSAGES,
    outbound_scope: "channel",
    label: "channel",
};

pub(super) const ALL_TABLES: [Rows; 18] = [
    ATTACHMENT_GC,
    DELETION_ADMINS,
    MESSAGE_DELETIONS,
    MLS_SNAPSHOT,
    MESSAGES,
    SESSIONS,
    GROUP_MLS_SNAPSHOT,
    GROUP_MESSAGES,
    GROUPS,
    CHANNEL_MESSAGES,
    CHANNELS,
    OUTBOUND_ATTEMPTS,
    MOSS_IDENTITY,
    DEVICE_LINK,
    CHAT_NAMES,
    ORG_ROSTERS,
    GROUP_COMMIT_LOG,
    ORG_RECORDS,
];
