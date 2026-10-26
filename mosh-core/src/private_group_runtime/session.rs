//! Session construction and atomic MLS restoring records.

use super::*;

impl ConversationSession for GroupSession {
    fn attach_persistence(&mut self, store: Option<Arc<Persistence>>) {
        self.deletions.store = store;
    }
    type Message = GroupMessage;
    type Record = PersistedGroupSession;

    fn conversation_id(&self) -> &str {
        &self.group_id
    }

    fn log(&self) -> &MessageLog<GroupMessage> {
        &self.messages
    }

    fn transfer(&self) -> Option<&Transfer> {
        Some(&self.transfer)
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.outbound_attempts
    }

    fn write_send_override(
        &self,
        store: &Persistence,
        message: &str,
    ) -> Result<bool, crate::persistence::PersistenceError> {
        self.write_publication(store, message)
    }

    fn record(&self) -> PersistedGroupSession {
        self.to_persisted_record()
    }

    fn write_extra(
        &self,
        persistence: &Persistence,
    ) -> Result<(), crate::persistence::PersistenceError> {
        let record = serde_json::to_vec(&self.to_persisted_record())
            .map_err(|error| crate::persistence::PersistenceError::Json(error.to_string()))?;
        // Rejoining can replace the signer while an older record survives a
        // refused close. The shared writer may repeat this same record safely.
        persistence.put_group_transition(&self.group_id, &record, &self.crypto.snapshot())
    }

    /// Until the MLS group exists the record's group id is an empty
    /// placeholder, and a group saved in that state cannot be rebuilt.
    fn record_is_final(&self) -> bool {
        self.crypto.group_id_bytes().is_some()
    }
}

pub(super) struct GroupSession {
    pub(super) plus_schedule: crate::plus::PlusSchedule,
    pub(super) deletions: crate::message_deletion::DeletionBook,
    pub(super) pending_join_package: Option<Vec<u8>>,
    pub(super) join_retry: super::pending_join::JoinRetry,
    pub(super) admission_replays:
        std::collections::BTreeMap<String, super::history::welcome::AdmissionReplay>,
    pub(super) group_id: String,
    pub(super) mesh_id: String,
    pub(super) label: Option<String>,
    pub(super) names: super::names::GroupNames,
    pub(super) names_last_sync: Option<std::time::Instant>,
    pub(super) display_name: String,
    pub(super) participant_id: String,
    pub(super) device_fingerprint: String,
    pub(super) creator_fingerprint: String,
    pub(super) current_admin_fingerprint: String,
    pub(super) is_admin: bool,
    pub(super) invite_uri: Option<String>,
    pub(super) joined: bool,
    pub(super) listen_port: u16,
    pub(super) static_peer: Option<String>,
    pub(super) node: Arc<MossNode>,
    pub(super) crypto: MlsSessionCrypto,
    pub(super) messages: MessageLog<GroupMessage>,
    pub(super) seen: SeenFrames,
    pub(super) recovery: crate::conversation::recovery::coordinator::Coordinator,
    pub(super) history_dispatch: crate::conversation::recovery::transport::DispatchGeneration,
    pub(super) history_head: Option<super::history::CurrentHead>,
    pub(super) history_membership: Option<(
        crate::mls_crypto::MlsHistoryContext,
        super::history::NativeCheckpoint,
    )>,
    // Epoch-ordered commit admission: dedups gossip duplicates and the
    // joiner's Welcome-carried admission commit, buffers out-of-order commits,
    // reports gaps for resync. Unbounded like its predecessor set — commits
    // only fire on membership change (rare).
    pub(super) sequencer: CommitSequencer,
    // Clone of the runtime's store: applied/produced commits land in
    // group_commit_log so the admin can serve ResyncRequests.
    pub(super) persistence: Option<Arc<Persistence>>,
    // Set when a commit gap could not be bridged by resync; surfaced to the
    // UI ("rejoin needed") instead of silently desyncing.
    pub(super) needs_rejoin: bool,
    pub(super) control_channel: String,
    pub(super) data_channel: String,
    pub(super) blob_channel: String,
    pub(super) transfer: Transfer,
    pub(super) publications: HashMap<String, super::history::PublicationAcceptance>,
    pub(super) outbound_attempts: HashMap<String, OutboundAttemptRecord>,
    pub(super) dm_offers: DmOffers,
    /// Org binding (ADR 0008). Some = control traffic is enveloped, the MLS
    /// credential is the moss peer-id and authority derives from the roster.
    pub(super) org_pubkey: Option<String>,
    /// Node identity key for enveloping; present iff `org_pubkey` is.
    pub(super) org_signer: Option<SigningKey>,
    /// Verified-roster cache keyed by the raw stored bytes, so repeated
    /// control messages don't re-verify an unchanged roster.
    pub(super) roster_cache: Option<(Vec<u8>, Roster)>,
    /// Exact verified org wrapper while admitting this control frame.
    pub(super) incoming_org_control: Option<Vec<u8>>,
    /// Commits from authors ahead of our roster (ADR 0005), retried on
    /// every roster change and dropped once the author is provably not an
    /// admin at their claimed version.
    pub(super) roster_lag: Vec<RosterLaggedCommit>,
    /// Roster version at the last lag-retry, so a change triggers exactly
    /// one retry pass.
    pub(super) last_roster_version_seen: Option<u64>,
    /// Fingerprint → wall-clock deadline of that member's typing hint. A
    /// refresh inside the window renews the entry; silence lets it lapse.
    pub(super) typing_members: HashMap<String, u64>,
    /// Fingerprint → the member's display name, learned from the
    /// authenticated frames that carry it (typing hints, messages). The
    /// roster view reads names from here instead of re-deriving them.
    pub(super) member_names: HashMap<String, String>,
    /// The send-cadence gate for this member's own TypingIndicator
    /// publishes.
    pub(super) typing_gate: TypingGate,
}

impl GroupSession {
    pub(super) fn new(
        record: PersistedGroupSession,
        node: Arc<MossNode>,
        crypto: MlsSessionCrypto,
        persistence: Option<Arc<Persistence>>,
        attachment_store: Arc<AttachmentStore>,
        org_signer: Option<SigningKey>,
    ) -> Self {
        Self {
            plus_schedule: Default::default(),
            deletions: crate::message_deletion::DeletionBook::new(
                format!("group:{}", record.group_id),
                GROUP_HISTORY,
                persistence.clone(),
            ),
            pending_join_package: None,
            join_retry: Default::default(),
            admission_replays: std::collections::BTreeMap::new(),
            control_channel: format!("{CONTROL_CHANNEL_PREFIX}{}", record.group_id),
            data_channel: format!("{DATA_CHANNEL_PREFIX}{}", record.group_id),
            blob_channel: format!("{BLOB_CHANNEL_PREFIX}{}", record.group_id),
            group_id: record.group_id,
            mesh_id: record.mesh_id,
            label: record.label,
            names: record.names,
            names_last_sync: None,
            display_name: record.display_name,
            participant_id: record.participant_id,
            device_fingerprint: record.device_fingerprint,
            creator_fingerprint: record.creator_fingerprint,
            current_admin_fingerprint: record.current_admin_fingerprint,
            is_admin: record.is_admin,
            invite_uri: record.invite_uri,
            joined: record.joined,
            listen_port: record.listen_port,
            static_peer: record.static_peer,
            org_pubkey: record.org_pubkey,
            node,
            crypto,
            persistence,
            org_signer,
            transfer: Transfer::new(attachment_store),
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            recovery: Default::default(),
            history_dispatch: Default::default(),
            history_head: None,
            history_membership: None,
            sequencer: CommitSequencer::new(),
            needs_rejoin: false,
            publications: HashMap::new(),
            outbound_attempts: HashMap::new(),
            dm_offers: DmOffers::default(),
            roster_cache: None,
            incoming_org_control: None,
            roster_lag: Vec::new(),
            last_roster_version_seen: None,
            typing_members: HashMap::new(),
            member_names: HashMap::new(),
            typing_gate: TypingGate::default(),
        }
    }
}

impl Drop for GroupSession {
    fn drop(&mut self) {
        self.history_dispatch.invalidate();
    }
}
