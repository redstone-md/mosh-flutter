use flutter_rust_bridge::frb;
use std::path::Path;

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::RngCore;
use redb::{Database, ReadableTable, TableDefinition};

use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::secure_storage::{OsSecureSecretStore, SecureSecretStore};

const NONCE_LEN: usize = 12;

/// Runtime status snapshot for the persistence module. Canonical home for the
/// readiness marker the diagnostics facade reports: backend id, database
/// path, availability, at-rest encryption flag, and an optional error string.
#[derive(serde::Serialize, Clone)]
#[frb(non_opaque)]
pub struct PersistenceRuntimeStatus {
    pub backend: String,
    pub database: String,
    pub available: bool,
    pub encrypted_at_rest: bool,
    pub error: Option<String>,
}

#[derive(Debug)]
pub enum PersistenceError {
    Crypto(String),
    Io(String),
    Db(String),
    Json(String),
    Keychain(String),
}

impl std::fmt::Display for PersistenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Crypto(e) => write!(f, "persistence crypto error: {e}"),
            Self::Io(e) => write!(f, "persistence io error: {e}"),
            Self::Db(e) => write!(f, "persistence db error: {e}"),
            Self::Json(e) => write!(f, "persistence json error: {e}"),
            Self::Keychain(e) => write!(f, "persistence keychain error: {e}"),
        }
    }
}
impl std::error::Error for PersistenceError {}

/// AES-256-GCM. Output layout: [12-byte nonce][ciphertext+tag].
pub fn encrypt_blob(dek: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, PersistenceError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(dek));
    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| PersistenceError::Crypto(e.to_string()))?;
    let mut out = Vec::with_capacity(NONCE_LEN + ct.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn decrypt_blob(dek: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, PersistenceError> {
    if blob.len() < NONCE_LEN {
        return Err(PersistenceError::Crypto("blob shorter than nonce".into()));
    }
    let (nonce_bytes, ct) = blob.split_at(NONCE_LEN);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(dek));
    cipher
        .decrypt(Nonce::from_slice(nonce_bytes), ct)
        .map_err(|e| PersistenceError::Crypto(e.to_string()))
}

const DEK_KEY: &str = "history-dek-v1";
const MLS_SNAPSHOT: TableDefinition<&str, &[u8]> = TableDefinition::new("mls_snapshot");
const MESSAGES: TableDefinition<&str, &[u8]> = TableDefinition::new("messages");
const SESSIONS: TableDefinition<&str, &[u8]> = TableDefinition::new("sessions");
const GROUP_MLS_SNAPSHOT: TableDefinition<&str, &[u8]> = TableDefinition::new("group_mls_snapshot");
const GROUP_MESSAGES: TableDefinition<&str, &[u8]> = TableDefinition::new("group_messages");
const GROUPS: TableDefinition<&str, &[u8]> = TableDefinition::new("groups");
const CHANNEL_MESSAGES: TableDefinition<&str, &[u8]> = TableDefinition::new("channel_messages");
const CHANNELS: TableDefinition<&str, &[u8]> = TableDefinition::new("channels");
const OUTBOUND_ATTEMPTS: TableDefinition<&str, &[u8]> = TableDefinition::new("outbound_attempts");
const MOSS_IDENTITY: TableDefinition<&str, &[u8]> = TableDefinition::new("moss_identity");
// Single-row table: the device's stable Moss transport identity (libp2p key).
const MOSS_IDENTITY_KEY: &str = "node-identity-v1";
// Key: org pubkey hex -> latest verified roster bytes (multi-org).
const ORG_ROSTERS: TableDefinition<&str, &[u8]> = TableDefinition::new("org_rosters");
// Key: "<group_id>/<epoch:020>" — zero-padded so lexicographic order == numeric.
const GROUP_COMMIT_LOG: TableDefinition<&str, &[u8]> = TableDefinition::new("group_commit_log");
// Key: org pubkey hex -> serialized PersistedOrgRecord (bundle + node config).
const ORG_RECORDS: TableDefinition<&str, &[u8]> = TableDefinition::new("org_records");

/// A table of encrypted rows keyed by a string.
type Rows = TableDefinition<'static, &'static str, &'static [u8]>;

/// Where one conversation kind keeps its history. A DM, a private group and a
/// public channel store the same rows; only the tables differ. Passing the
/// names in as data is what lets the code that reads and writes them be
/// written once instead of three times.
#[derive(Clone, Copy)]
pub struct HistoryTables {
    /// One row per conversation: the record it is rebuilt from at startup.
    conversations: Rows,
    /// One row per message, keyed by conversation, send time and message id.
    messages: Rows,
    /// The key prefix this kind's outbound attempts share.
    pub outbound_scope: &'static str,
    /// What one conversation is called in a warning about an unreadable row.
    pub label: &'static str,
}

pub const DM_HISTORY: HistoryTables = HistoryTables {
    conversations: SESSIONS,
    messages: MESSAGES,
    outbound_scope: "private_dm",
    label: "session",
};

pub const GROUP_HISTORY: HistoryTables = HistoryTables {
    conversations: GROUPS,
    messages: GROUP_MESSAGES,
    outbound_scope: "private_group",
    label: "group",
};

pub const CHANNEL_HISTORY: HistoryTables = HistoryTables {
    conversations: CHANNELS,
    messages: CHANNEL_MESSAGES,
    outbound_scope: "channel",
    label: "channel",
};

pub struct Persistence {
    db: Database,
    dek: [u8; 32],
}

/// Where the DEK for the database at `path` lives. macOS keeps it in a file
/// beside the database (see `file_secret_store` for why); every other desktop
/// keeps it in the OS keychain.
#[cfg(target_os = "macos")]
fn dek_store(path: &Path) -> Box<dyn SecureSecretStore> {
    match path.parent() {
        Some(dir) => Box::new(crate::file_secret_store::FileSecretStore::new(dir)),
        None => Box::new(OsSecureSecretStore),
    }
}

#[cfg(not(target_os = "macos"))]
fn dek_store(_path: &Path) -> Box<dyn SecureSecretStore> {
    Box::new(OsSecureSecretStore)
}

impl Persistence {
    /// Open (or create) the encrypted DB at `path`, loading the DEK from
    /// `dek_store` (creating + storing a new random DEK on first run).
    pub fn open(path: &Path) -> Result<Self, PersistenceError> {
        Self::open_with_key(path, DEK_KEY)
    }

    /// [`open`] against an explicit keychain key.
    ///
    /// Exists so a test can exercise the real keychain path -- the mint,
    /// store and reload that `open` performs -- WITHOUT touching the
    /// production `history-dek-v1` entry. A test that used the production key
    /// and deleted it on teardown would destroy the DEK of whoever ran
    /// `cargo test`, leaving their real `history.redb` encrypted with a key
    /// that no longer exists: the app then fails closed on every later start
    /// and the history is gone for good.
    pub(crate) fn open_with_key(path: &Path, dek_key: &str) -> Result<Self, PersistenceError> {
        let store = dek_store(path);
        let db_exists = path.exists();
        let dek = match store.load_secret(dek_key) {
            Ok(bytes) if bytes.len() == 32 => {
                let mut d = [0u8; 32];
                d.copy_from_slice(&bytes);
                d
            }
            Ok(_) => {
                // Key present but wrong size = corrupt; fail closed, never overwrite.
                return Err(PersistenceError::Keychain(
                    "stored DEK has unexpected length".into(),
                ));
            }
            Err(e) => {
                if db_exists {
                    // Existing database but DEK unavailable: fail closed. Minting a new
                    // key here would permanently orphan all persisted history.
                    return Err(PersistenceError::Keychain(format!(
                        "DEK unavailable but database exists: {e}"
                    )));
                }
                // Genuine first run: mint and store a fresh DEK.
                let mut d = [0u8; 32];
                rand::rngs::OsRng.fill_bytes(&mut d);
                store
                    .save_secret(dek_key, &d)
                    .map_err(|err| PersistenceError::Keychain(err.to_string()))?;
                d
            }
        };
        let db = Database::create(path).map_err(|e| PersistenceError::Db(e.to_string()))?;
        let wtx = db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            wtx.open_table(MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(SESSIONS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUPS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(CHANNEL_MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(CHANNELS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(OUTBOUND_ATTEMPTS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(MOSS_IDENTITY)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(ORG_ROSTERS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_COMMIT_LOG)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(ORG_RECORDS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        Ok(Self { db, dek })
    }

    /// Open (or create) the encrypted DB at `path` using a caller-supplied
    /// DEK instead of the OS keychain (ADR 0011 mobile-inject path). Public
    /// but internal: the only external caller is `api::private_dm`'s
    /// `construct_runtime`, when Dart has injected a Keystore-minted DEK via
    /// `set_history_dek`. This is NOT exposed across `flutter_rust_bridge`
    /// (the bridge surface for injection is `set_history_dek` only). The
    /// caller's DEK is trusted as-is -- the keychain mint/load branch is
    /// skipped entirely, so a wrong DEK surfaces later as a redb `Crypto`
    /// decrypt failure (the `open` path fail-closes on a missing DEK when
    /// the DB exists; the inject path defers that mismatch to read time,
    /// the correct posture for a caller that already owns the secret).
    pub fn open_with_dek(path: &Path, dek: [u8; 32]) -> Result<Self, PersistenceError> {
        let db = Database::create(path).map_err(|e| PersistenceError::Db(e.to_string()))?;
        let wtx = db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            wtx.open_table(MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(SESSIONS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUPS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(CHANNEL_MESSAGES)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(CHANNELS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(OUTBOUND_ATTEMPTS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(MOSS_IDENTITY)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(ORG_ROSTERS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(GROUP_COMMIT_LOG)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            wtx.open_table(ORG_RECORDS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        Ok(Self { db, dek })
    }

    fn put(
        &self,
        table: TableDefinition<&str, &[u8]>,
        key: &str,
        plaintext: &[u8],
    ) -> Result<(), PersistenceError> {
        let blob = encrypt_blob(&self.dek, plaintext)?;
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut t = wtx
                .open_table(table)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            t.insert(key, blob.as_slice())
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    fn get(
        &self,
        table: TableDefinition<&str, &[u8]>,
        key: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let t = rtx
            .open_table(table)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        match t
            .get(key)
            .map_err(|e| PersistenceError::Db(e.to_string()))?
        {
            Some(g) => Ok(Some(decrypt_blob(&self.dek, g.value())?)),
            None => Ok(None),
        }
    }

    fn range_prefix(
        &self,
        table: TableDefinition<&str, &[u8]>,
        prefix: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        let lo = format!("{prefix}\u{0001}");
        let hi = format!("{prefix}\u{0002}");
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let t = rtx
            .open_table(table)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let mut out = Vec::new();
        for item in t
            .range(lo.as_str()..hi.as_str())
            .map_err(|e| PersistenceError::Db(e.to_string()))?
        {
            let (_k, v) = item.map_err(|e| PersistenceError::Db(e.to_string()))?;
            out.push(decrypt_blob(&self.dek, v.value())?);
        }
        Ok(out)
    }

    fn delete_prefix(
        &self,
        wtx: &redb::WriteTransaction,
        table: TableDefinition<&str, &[u8]>,
        prefix: &str,
    ) -> Result<(), PersistenceError> {
        let lo = format!("{prefix}\u{0001}");
        let hi = format!("{prefix}\u{0002}");
        let mut rows = wtx
            .open_table(table)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let keys: Vec<String> = rows
            .range(lo.as_str()..hi.as_str())
            .map_err(|e| PersistenceError::Db(e.to_string()))?
            .map(|item| {
                item.map(|(k, _)| k.value().to_string())
                    .map_err(|e| PersistenceError::Db(e.to_string()))
            })
            .collect::<Result<_, _>>()?;
        for key in keys {
            rows.remove(key.as_str())
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        Ok(())
    }

    fn outbound_attempt_prefix(scope: &str, conversation_id: &str) -> String {
        format!("{scope}\u{0001}{conversation_id}")
    }

    fn outbound_attempt_key(scope: &str, conversation_id: &str, message_id: &str) -> String {
        format!(
            "{}\u{0001}{message_id}",
            Self::outbound_attempt_prefix(scope, conversation_id)
        )
    }

    pub fn put_mls_snapshot(
        &self,
        session_id: &str,
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(MLS_SNAPSHOT, session_id, snapshot)
    }
    pub fn get_mls_snapshot(&self, session_id: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(MLS_SNAPSHOT, session_id)
    }

    /// The record a conversation is rebuilt from at startup.
    pub fn put_conversation(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(tables.conversations, conversation_id, json)
    }

    /// Every conversation record of one kind. An unreadable row is skipped
    /// with a warning, so one bad record cannot block startup.
    pub fn list_conversations(
        &self,
        tables: HistoryTables,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let t = rtx
            .open_table(tables.conversations)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let mut out = Vec::new();
        for item in t.iter().map_err(|e| PersistenceError::Db(e.to_string()))? {
            let (k, v) = item.map_err(|e| PersistenceError::Db(e.to_string()))?;
            match decrypt_blob(&self.dek, v.value()) {
                Ok(plain) => out.push(plain),
                Err(e) => dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    tables.label,
                    &format!(
                        "skipping undecryptable {} row {}: {e}",
                        tables.label,
                        k.value()
                    ),
                ),
            }
        }
        Ok(out)
    }

    /// Keyed so a lexicographic scan hands the messages back oldest first.
    pub fn append_history_message(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        let key = Self::history_message_key(conversation_id, sent_at_ms, message_id);
        self.put(tables.messages, &key, json)
    }

    /// Both rows one send leaves behind, in a single transaction: the message
    /// in its history table, and the attempt record that holds the payload —
    /// or the removal of that record, once the send is over.
    ///
    /// One transaction because the two rows are one fact. Written separately
    /// they can tear, and a message row that lands without its attempt comes
    /// back Pending with nothing to settle it and no bytes to replay.
    pub fn commit_send(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        message_json: &[u8],
        attempt_json: Option<&[u8]>,
    ) -> Result<(), PersistenceError> {
        let message_key = Self::history_message_key(conversation_id, sent_at_ms, message_id);
        let attempt_key =
            Self::outbound_attempt_key(tables.outbound_scope, conversation_id, message_id);
        let message_blob = encrypt_blob(&self.dek, message_json)?;
        let attempt_blob = attempt_json
            .map(|json| encrypt_blob(&self.dek, json))
            .transpose()?;
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut messages = wtx
                .open_table(tables.messages)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            messages
                .insert(message_key.as_str(), message_blob.as_slice())
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            let mut attempts = wtx
                .open_table(OUTBOUND_ATTEMPTS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            match attempt_blob.as_deref() {
                Some(blob) => attempts
                    .insert(attempt_key.as_str(), blob)
                    .map(|_| ())
                    .map_err(|e| PersistenceError::Db(e.to_string()))?,
                None => attempts
                    .remove(attempt_key.as_str())
                    .map(|_| ())
                    .map_err(|e| PersistenceError::Db(e.to_string()))?,
            }
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    /// Keyed so a lexicographic scan hands the messages back oldest first.
    fn history_message_key(conversation_id: &str, sent_at_ms: u64, message_id: &str) -> String {
        format!("{conversation_id}\u{0001}{sent_at_ms:020}\u{0001}{message_id}")
    }

    pub fn list_history_messages(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.range_prefix(tables.messages, conversation_id)
    }

    pub fn put_session(&self, session_id: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(DM_HISTORY, session_id, json)
    }
    pub fn list_sessions(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(DM_HISTORY)
    }

    pub fn append_message(
        &self,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(DM_HISTORY, conversation_id, sent_at_ms, message_id, json)
    }
    pub fn list_messages(&self, conversation_id: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(DM_HISTORY, conversation_id)
    }

    pub fn put_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        let key = Self::outbound_attempt_key(scope, conversation_id, message_id);
        self.put(OUTBOUND_ATTEMPTS, &key, json)
    }

    pub fn get_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        let key = format!(
            "{}\u{0001}{message_id}",
            Self::outbound_attempt_prefix(scope, conversation_id)
        );
        self.get(OUTBOUND_ATTEMPTS, &key)
    }

    pub fn list_outbound_attempts(
        &self,
        scope: &str,
        conversation_id: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.range_prefix(
            OUTBOUND_ATTEMPTS,
            &Self::outbound_attempt_prefix(scope, conversation_id),
        )
    }

    pub fn delete_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
    ) -> Result<(), PersistenceError> {
        let key = Self::outbound_attempt_key(scope, conversation_id, message_id);
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut rows = wtx
                .open_table(OUTBOUND_ATTEMPTS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            rows.remove(key.as_str())
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    /// Permanently remove a conversation: its session record, MLS snapshot and
    /// every persisted message. Used when the user deletes a chat so it does
    /// not return on the next launch.
    pub fn delete_session(&self, session_id: &str) -> Result<(), PersistenceError> {
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut sessions = wtx
                .open_table(SESSIONS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            sessions
                .remove(session_id)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        {
            let mut snapshot = wtx
                .open_table(MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            snapshot
                .remove(session_id)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        {
            self.delete_prefix(&wtx, MESSAGES, session_id)?;
        }
        {
            self.delete_prefix(
                &wtx,
                OUTBOUND_ATTEMPTS,
                &Self::outbound_attempt_prefix(DM_HISTORY.outbound_scope, session_id),
            )?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    pub fn put_group_mls_snapshot(
        &self,
        group_id: &str,
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(GROUP_MLS_SNAPSHOT, group_id, snapshot)
    }

    pub fn get_group_mls_snapshot(
        &self,
        group_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(GROUP_MLS_SNAPSHOT, group_id)
    }

    pub fn put_group(&self, group_id: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(GROUP_HISTORY, group_id, json)
    }

    pub fn list_groups(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(GROUP_HISTORY)
    }

    pub fn append_group_message(
        &self,
        group_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(GROUP_HISTORY, group_id, sent_at_ms, message_id, json)
    }

    pub fn list_group_messages(&self, group_id: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(GROUP_HISTORY, group_id)
    }

    /// Permanently remove a private group: its group record, MLS snapshot and
    /// every persisted message.
    pub fn delete_group(&self, group_id: &str) -> Result<(), PersistenceError> {
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut groups = wtx
                .open_table(GROUPS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            groups
                .remove(group_id)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        {
            let mut snapshot = wtx
                .open_table(GROUP_MLS_SNAPSHOT)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            snapshot
                .remove(group_id)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        {
            self.delete_prefix(&wtx, GROUP_MESSAGES, group_id)?;
        }
        {
            self.delete_prefix(
                &wtx,
                OUTBOUND_ATTEMPTS,
                &Self::outbound_attempt_prefix(GROUP_HISTORY.outbound_scope, group_id),
            )?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    pub fn put_channel(&self, name: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(CHANNEL_HISTORY, name, json)
    }

    pub fn list_channels(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(CHANNEL_HISTORY)
    }

    pub fn append_channel_message(
        &self,
        name: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(CHANNEL_HISTORY, name, sent_at_ms, message_id, json)
    }

    pub fn list_channel_messages(&self, name: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(CHANNEL_HISTORY, name)
    }

    pub fn delete_channel(&self, name: &str) -> Result<(), PersistenceError> {
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut channels = wtx
                .open_table(CHANNELS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            channels
                .remove(name)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        {
            self.delete_prefix(&wtx, CHANNEL_MESSAGES, name)?;
        }
        {
            self.delete_prefix(
                &wtx,
                OUTBOUND_ATTEMPTS,
                &Self::outbound_attempt_prefix(CHANNEL_HISTORY.outbound_scope, name),
            )?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    /// The device's stable Moss transport identity (encrypted like everything
    /// else). Persisting it keeps the node's peer-id constant across restarts,
    /// which is required for peers to re-establish a connection instead of
    /// flapping.
    pub fn put_moss_identity(&self, raw: &[u8]) -> Result<(), PersistenceError> {
        self.put(MOSS_IDENTITY, MOSS_IDENTITY_KEY, raw)
    }
    pub fn get_moss_identity(&self) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(MOSS_IDENTITY, MOSS_IDENTITY_KEY)
    }

    pub fn put_org_roster(
        &self,
        org_pubkey: &str,
        roster_bytes: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(ORG_ROSTERS, org_pubkey, roster_bytes)
    }

    pub fn get_org_roster(&self, org_pubkey: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(ORG_ROSTERS, org_pubkey)
    }

    pub fn list_org_rosters(&self) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let table = rtx
            .open_table(ORG_ROSTERS)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let mut out = Vec::new();
        for entry in table
            .iter()
            .map_err(|e| PersistenceError::Db(e.to_string()))?
        {
            let (key, value) = entry.map_err(|e| PersistenceError::Db(e.to_string()))?;
            out.push((
                key.value().to_string(),
                decrypt_blob(&self.dek, value.value())?,
            ));
        }
        Ok(out)
    }

    pub fn put_org_record(&self, org_pubkey: &str, record: &[u8]) -> Result<(), PersistenceError> {
        self.put(ORG_RECORDS, org_pubkey, record)
    }

    pub fn get_org_record(&self, org_pubkey: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(ORG_RECORDS, org_pubkey)
    }

    pub fn list_org_records(&self) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let table = rtx
            .open_table(ORG_RECORDS)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let mut out = Vec::new();
        for entry in table
            .iter()
            .map_err(|e| PersistenceError::Db(e.to_string()))?
        {
            let (key, value) = entry.map_err(|e| PersistenceError::Db(e.to_string()))?;
            out.push((
                key.value().to_string(),
                decrypt_blob(&self.dek, value.value())?,
            ));
        }
        Ok(out)
    }

    /// Leaving an org drops both its record and its cached roster atomically.
    pub fn delete_org(&self, org_pubkey: &str) -> Result<(), PersistenceError> {
        let wtx = self
            .db
            .begin_write()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        {
            let mut records = wtx
                .open_table(ORG_RECORDS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            records
                .remove(org_pubkey)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            let mut rosters = wtx
                .open_table(ORG_ROSTERS)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
            rosters
                .remove(org_pubkey)
                .map_err(|e| PersistenceError::Db(e.to_string()))?;
        }
        wtx.commit()
            .map_err(|e| PersistenceError::Db(e.to_string()))
    }

    fn commit_log_key(group_id: &str, epoch: u64) -> String {
        format!("{group_id}/{epoch:020}")
    }

    pub fn append_group_commit(
        &self,
        group_id: &str,
        epoch: u64,
        commit: &[u8],
    ) -> Result<(), PersistenceError> {
        // '/' is the key separator; a group_id containing it would collide
        // with a sibling group's key space and poison its resync range.
        // group_ids can arrive in remote offers, so fail closed.
        if group_id.contains('/') {
            return Err(PersistenceError::Db(format!(
                "group_id must not contain '/': {group_id}"
            )));
        }
        self.put(
            GROUP_COMMIT_LOG,
            &Self::commit_log_key(group_id, epoch),
            commit,
        )
    }

    /// Commits for `group_id` with epoch >= from_epoch, ascending. Backing
    /// store for the resync path (spec §7). Never pruned in v1.
    pub fn list_group_commits_from(
        &self,
        group_id: &str,
        from_epoch: u64,
    ) -> Result<Vec<(u64, Vec<u8>)>, PersistenceError> {
        let rtx = self
            .db
            .begin_read()
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let table = rtx
            .open_table(GROUP_COMMIT_LOG)
            .map_err(|e| PersistenceError::Db(e.to_string()))?;
        let start = Self::commit_log_key(group_id, from_epoch);
        let end = format!("{group_id}/{}", "9".repeat(21)); // beyond any 20-digit epoch
        let prefix = format!("{group_id}/");
        let mut out = Vec::new();
        for entry in table
            .range(start.as_str()..end.as_str())
            .map_err(|e| PersistenceError::Db(e.to_string()))?
        {
            let (key, value) = entry.map_err(|e| PersistenceError::Db(e.to_string()))?;
            let key = key.value();
            let Some(epoch_str) = key.strip_prefix(&prefix) else {
                continue;
            };
            // Skip foreign/malformed keys instead of failing the whole read:
            // one bad key must not DoS a group's resync.
            if epoch_str.len() != 20 || !epoch_str.bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            let Ok(epoch) = epoch_str.parse::<u64>() else {
                continue;
            };
            out.push((epoch, decrypt_blob(&self.dek, value.value())?));
        }
        Ok(out)
    }
}

impl crate::moss_ffi::MossKeyStore for Persistence {
    fn load_identity(&self) -> Option<Vec<u8>> {
        match self.get_moss_identity() {
            Ok(value) => value,
            Err(e) => {
                dlog::write(
                    LogLevel::Error,
                    kinds::IDENTITY,
                    "",
                    &format!("moss identity load failed: {e}"),
                );
                None
            }
        }
    }

    fn save_identity(&self, bytes: &[u8]) {
        if let Err(e) = self.put_moss_identity(bytes) {
            dlog::write(
                LogLevel::Error,
                kinds::IDENTITY,
                "",
                &format!("moss identity save failed: {e}"),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blob_round_trips() {
        let dek = [7u8; 32];
        let blob = encrypt_blob(&dek, b"hello history").unwrap();
        assert_ne!(&blob[12..], b"hello history");
        assert_eq!(decrypt_blob(&dek, &blob).unwrap(), b"hello history");
    }

    #[test]
    fn tamper_fails() {
        let dek = [7u8; 32];
        let mut blob = encrypt_blob(&dek, b"secret").unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0xFF;
        assert!(decrypt_blob(&dek, &blob).is_err());
    }

    #[test]
    fn org_roster_roundtrip_multi_org() {
        let path = std::env::temp_dir().join(format!("mosh-org-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [1u8; 32]).unwrap();

        p.put_org_roster("aa11", b"roster-a-v1").unwrap();
        p.put_org_roster("bb22", b"roster-b-v1").unwrap();
        p.put_org_roster("aa11", b"roster-a-v2").unwrap(); // overwrite = latest wins
        assert_eq!(p.get_org_roster("aa11").unwrap().unwrap(), b"roster-a-v2");
        assert_eq!(p.get_org_roster("none").unwrap(), None);
        let all = p.list_org_rosters().unwrap();
        assert_eq!(all.len(), 2);
        assert!(all.iter().any(|(k, v)| k == "bb22" && v == b"roster-b-v1"));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn group_commit_log_ordered_range() {
        let path = std::env::temp_dir().join(format!("mosh-clog-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [1u8; 32]).unwrap();

        p.append_group_commit("g1", 2, b"c2").unwrap();
        p.append_group_commit("g1", 10, b"c10").unwrap();
        p.append_group_commit("g1", 3, b"c3").unwrap();
        p.append_group_commit("g2", 1, b"other").unwrap();
        let commits = p.list_group_commits_from("g1", 3).unwrap();
        assert_eq!(commits, vec![(3, b"c3".to_vec()), (10, b"c10".to_vec())]);
        assert!(p.list_group_commits_from("g3", 0).unwrap().is_empty());

        // '/' in group_id would collide with a sibling group's key space.
        assert!(p.append_group_commit("g1/x", 1, b"evil").is_err());

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn moss_identity_round_trips() {
        let path = std::env::temp_dir().join(format!("mosh-moss-id-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [3u8; 32]).unwrap();

        assert!(p.get_moss_identity().unwrap().is_none());
        let identity = vec![9u8; 129];
        p.put_moss_identity(&identity).unwrap();
        assert_eq!(p.get_moss_identity().unwrap(), Some(identity));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn delete_session_removes_record_snapshot_and_messages() {
        let path = std::env::temp_dir().join(format!("mosh-del-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [5u8; 32]).unwrap();

        p.put_session("s1", b"rec").unwrap();
        p.put_mls_snapshot("s1", b"snap").unwrap();
        p.append_message("s1", 1, "m1", b"hi").unwrap();
        p.append_message("s1", 2, "m2", b"yo").unwrap();
        // Unrelated conversation must survive.
        p.put_session("s2", b"rec2").unwrap();
        p.append_message("s2", 1, "x", b"keep").unwrap();

        p.delete_session("s1").unwrap();

        assert!(p.get_mls_snapshot("s1").unwrap().is_none());
        assert!(p.list_messages("s1").unwrap().is_empty());
        assert_eq!(p.list_sessions().unwrap().len(), 1);
        assert_eq!(p.list_messages("s2").unwrap().len(), 1);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn messages_round_trip_in_time_order() {
        let dir = std::env::temp_dir().join(format!("mosh-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("msgs.redb");
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [3u8; 32]).unwrap();

        p.append_message("conv-A", 200, "m2", b"second").unwrap();
        p.append_message("conv-A", 100, "m1", b"first").unwrap();
        p.append_message("conv-B", 150, "x", b"other").unwrap();

        let msgs = p.list_messages("conv-A").unwrap();
        assert_eq!(msgs, vec![b"first".to_vec(), b"second".to_vec()]);
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn messages_ordered_within_same_millisecond_batch() {
        let dir = std::env::temp_dir().join(format!("mosh-ms-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ms-batch.redb");
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [5u8; 32]).unwrap();

        let ts = 1_700_000_000_000u64;
        // Insert 12 messages in the SAME millisecond, ids built like the runtime
        // does after FIX 2 (zero-padded index), out of natural insertion order.
        for i in (0..12u32).rev() {
            let id = format!("{ts}-{i:06}");
            let body = format!("m{i}");
            p.append_message("conv", ts, &id, body.as_bytes()).unwrap();
        }
        let got: Vec<String> = p
            .list_messages("conv")
            .unwrap()
            .into_iter()
            .map(|b| String::from_utf8(b).unwrap())
            .collect();
        let want: Vec<String> = (0..12).map(|i| format!("m{i}")).collect();
        assert_eq!(got, want, "same-ms messages must come back in index order");
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn group_records_messages_and_snapshot_round_trip_then_delete() {
        let dir = std::env::temp_dir().join(format!("mosh-groups-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("groups.redb");
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [11u8; 32]).unwrap();

        p.put_group("g1", br#"{"group_id":"g1"}"#).unwrap();
        p.put_group_mls_snapshot("g1", b"group-snapshot").unwrap();
        p.append_group_message("g1", 20, "m2", br#"{"body":"second"}"#)
            .unwrap();
        p.append_group_message("g1", 10, "m1", br#"{"body":"first"}"#)
            .unwrap();

        assert_eq!(p.list_groups().unwrap().len(), 1);
        assert_eq!(
            p.get_group_mls_snapshot("g1").unwrap().unwrap(),
            b"group-snapshot"
        );
        let rows = p.list_group_messages("g1").unwrap();
        assert_eq!(rows[0], br#"{"body":"first"}"#);
        assert_eq!(rows[1], br#"{"body":"second"}"#);

        p.delete_group("g1").unwrap();
        assert!(p.list_groups().unwrap().is_empty());
        assert!(p.get_group_mls_snapshot("g1").unwrap().is_none());
        assert!(p.list_group_messages("g1").unwrap().is_empty());

        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn channel_records_and_messages_round_trip_then_delete() {
        let dir = std::env::temp_dir().join(format!("mosh-channels-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("channels.redb");
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [15u8; 32]).unwrap();

        p.put_channel("general", br#"{"name":"general"}"#).unwrap();
        p.append_channel_message("general", 20, "m2", br#"{"body":"second"}"#)
            .unwrap();
        p.append_channel_message("general", 10, "m1", br#"{"body":"first"}"#)
            .unwrap();

        assert_eq!(p.list_channels().unwrap().len(), 1);
        let rows = p.list_channel_messages("general").unwrap();
        assert_eq!(rows[0], br#"{"body":"first"}"#);
        assert_eq!(rows[1], br#"{"body":"second"}"#);

        p.delete_channel("general").unwrap();
        assert!(p.list_channels().unwrap().is_empty());
        assert!(p.list_channel_messages("general").unwrap().is_empty());

        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn outbound_attempts_round_trip_in_order_and_delete_with_conversation() {
        let dir = std::env::temp_dir().join(format!("mosh-outbound-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("outbound.redb");
        let _ = std::fs::remove_file(&path);
        let p = Persistence::open_with_dek(&path, [21u8; 32]).unwrap();

        p.put_outbound_attempt("private_dm", "s1", "m2", br#"{"message_id":"m2"}"#)
            .unwrap();
        p.put_outbound_attempt("private_dm", "s1", "m1", br#"{"message_id":"m1"}"#)
            .unwrap();
        p.put_outbound_attempt("private_group", "g1", "gm1", br#"{"message_id":"gm1"}"#)
            .unwrap();
        p.put_outbound_attempt("channel", "general", "cm1", br#"{"message_id":"cm1"}"#)
            .unwrap();

        assert_eq!(
            p.get_outbound_attempt("private_dm", "s1", "m1")
                .unwrap()
                .unwrap(),
            br#"{"message_id":"m1"}"#
        );
        assert_eq!(
            p.list_outbound_attempts("private_dm", "s1").unwrap(),
            vec![
                br#"{"message_id":"m1"}"#.to_vec(),
                br#"{"message_id":"m2"}"#.to_vec()
            ]
        );

        p.delete_session("s1").unwrap();
        p.delete_group("g1").unwrap();
        p.delete_channel("general").unwrap();

        assert!(p
            .list_outbound_attempts("private_dm", "s1")
            .unwrap()
            .is_empty());
        assert!(p
            .list_outbound_attempts("private_group", "g1")
            .unwrap()
            .is_empty());
        assert!(p
            .list_outbound_attempts("channel", "general")
            .unwrap()
            .is_empty());

        std::fs::remove_file(&path).ok();
    }

    // M-3 (ADR 0011 mobile-inject path): prove the Keystore-injected DEK
    // round-trips a history row across a drop-and-reopen, WITHOUT touching
    // the OS keychain. This is the host-runnable half of the mobile
    // platform channel: `construct_runtime` calls `open_with_dek(path, *dek)`
    // when Dart has injected a DEK via `set_history_dek`, so this test drives
    // that exact call (the "internal set_history_dek equivalent" -- a known
    // 32-byte DEK handed straight to `open_with_dek`, bypassing the
    // process-global OnceLock the live `set_history_dek` writes, which is
    // idempotent-once and not resettable between tests). The keychain is
    // never read or written on this path: `open_with_dek` skips the
    // `OsSecureSecretStore` mint/load branch entirely (confirmed by code --
    // it never constructs `OsSecureSecretStore` nor calls `load_secret` /
    // `save_secret` / `delete_secret`), so the host Windows Credential
    // Manager is not touched. Serial under --test-threads=1 alongside the
    // other persistence tests; cleans its unique temp file in teardown.
    #[test]
    fn open_with_dek_round_trips_session_across_reopen_without_keychain() {
        let path = std::env::temp_dir().join(format!(
            "mosh-m3-inject-{}-{}.redb",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        let dek = [42u8; 32];

        // First open under the injected DEK: write a session row.
        {
            let p = Persistence::open_with_dek(&path, dek).expect("first open_with_dek");
            p.put_session("m3-session", b"{\"hello\":\"inject\"}")
                .expect("session should persist under injected DEK");
        }

        // Reopen the SAME path with the SAME injected DEK: the row must
        // decrypt and round-trip. A wrong DEK here would surface as a redb
        // Crypto decrypt failure (the mismatch the inject path defers to
        // read time).
        {
            let p = Persistence::open_with_dek(&path, dek).expect("reopen open_with_dek");
            let sessions = p.list_sessions().expect("sessions should list");
            assert!(
                sessions.iter().any(|row| row == b"{\"hello\":\"inject\"}"),
                "persisted session must round-trip and decrypt under the injected DEK: {sessions:?}"
            );
        }

        std::fs::remove_file(&path).ok();
    }
}
