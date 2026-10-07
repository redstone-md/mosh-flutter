//! Signed protocol boundary proof. Each worker uses a real Moss node and redb.
use super::{records::TextRecord, types::*, *};
use crate::attachment_store::AttachmentStore;
use crate::mls_crypto::MlsSessionCrypto;
use crate::moss_ffi::{set_moss_keystore, MossFfiRuntime};
use crate::persistence::Persistence;
use crate::private_dm_runtime::devices::{
    proof::{DevicePacket, IdentityClaim},
    types::*,
};
use crate::private_dm_runtime::{PrivateDmRuntime, SessionSnapshot, StartSessionRequest};
use crate::shared_node::SharedMossNode;
use std::{path::PathBuf, sync::Arc};

struct Fixture {
    runtime: PrivateDmRuntime,
    receiver: DeviceIdentity,
    source: DeviceIdentity,
    contact: DeviceIdentity,
    outsider: DeviceIdentity,
    session: String,
    dir: PathBuf,
    peers: std::collections::HashMap<String, MlsSessionCrypto>,
    received_ms: u64,
}

fn identity(dir: &std::path::Path, name: &str) -> DeviceIdentity {
    let store = Arc::new(Persistence::open_with_dek(&dir.join(name), rand::random()).unwrap());
    let peer_key = ed25519_dalek::SigningKey::generate(&mut rand::rngs::OsRng);
    DeviceIdentity::open(store, &hex::encode(peer_key.verifying_key().as_bytes())).unwrap()
}

fn adopt(identity: &mut DeviceIdentity, roster: DeviceRoster) {
    let mut record = identity.record.clone();
    record.roster = roster;
    identity.update(record).unwrap();
}

impl Fixture {
    fn new() -> Self {
        Self::with_clients(true)
    }

    fn with_clients(include_source: bool) -> Self {
        let dir =
            std::env::temp_dir().join(format!("mosh-history-packets-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&dir).unwrap();
        let store = Arc::new(
            Persistence::open_with_dek(&dir.join("receiver.redb"), rand::random()).unwrap(),
        );
        set_moss_keystore(store.clone());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        moss.install_keystore().unwrap();
        let shared = SharedMossNode::new(moss);
        let node = shared.acquire(0, None).unwrap();
        let mut receiver =
            DeviceIdentity::open(store.clone(), &node.public_key_hex().unwrap()).unwrap();
        let mut source = identity(&dir, "source.redb");
        let contact = identity(&dir, "contact.redb");
        let outsider = identity(&dir, "outsider.redb");
        let roster = receiver
            .roster()
            .extend(source.device().clone(), &receiver.key())
            .unwrap();
        adopt(&mut receiver, roster.clone());
        adopt(&mut source, roster);
        let attachments = Arc::new(AttachmentStore::new(dir.clone()).unwrap());
        let mut runtime =
            PrivateDmRuntime::from_shared_node(shared.clone(), attachments, Some(store));
        let invite = runtime
            .create_invite(StartSessionRequest {
                display_name: "Original".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap();
        shared.release();
        let mut fixture = Self {
            runtime,
            receiver,
            source,
            contact,
            outsider,
            session: invite.session_id,
            dir,
            peers: Default::default(),
            received_ms: 0,
        };
        fixture.admit_clients(include_source);
        fixture
    }

    fn admit_clients(&mut self, include_source: bool) {
        let session = self.runtime.session_mut(&self.session).unwrap();
        let mut clients = vec![IdentityClaim::create(
            &self.receiver,
            &self.session,
            &session.crypto.signer_public(),
            "Original",
        )
        .unwrap()];
        for identity in [&self.source, &self.contact] {
            if !include_source && identity.device().device_id == self.source.device().device_id {
                continue;
            }
            let mut crypto = MlsSessionCrypto::new(&identity.device().device_id).unwrap();
            let outcome = session
                .crypto
                .add_members(&[&crypto.key_package_bytes().unwrap()])
                .unwrap();
            for peer in self.peers.values_mut() {
                peer.process_commit(&outcome.commit_bytes).unwrap();
            }
            crypto
                .join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
                .unwrap();
            clients.push(
                IdentityClaim::create(identity, &self.session, &crypto.signer_public(), "Original")
                    .unwrap(),
            );
            self.peers
                .insert(identity.device().device_id.clone(), crypto);
        }
        session.membership = Some(DeviceMembership {
            topology: DmTopology {
                own_user_id: self.receiver.roster().user_id(),
                clients,
                rosters: vec![
                    self.receiver.roster().clone(),
                    self.contact.roster().clone(),
                ],
            },
            joining: None,
            delivery: None,
            receipt_targets: Default::default(),
            delivered_ids: Vec::new(),
            history_import: include_source
                .then(|| HistoryImport::new("packets", self.source.device())),
            history_exports: Vec::new(),
            recovery: None,
            recovery_exports: Vec::new(),
            epoch_records: Vec::new(),
            removals: Vec::new(),
            revoked: false,
            pending_rosters: Vec::new(),
        });
        // Model the newly admitted recipient, whose persisted Welcome proves
        // admission even before its first complete history row is visible.
        session.role = crate::private_dm_runtime::SessionRole::Bob;
        session.peer_joined = true;
        session.record_dirty = true;
        self.runtime.sessions.persist_tail().unwrap();
    }

    fn batch(&self, offset: usize, records: Vec<TextRecord>) -> HistoryBatch {
        HistoryBatch {
            session_id: self.session.clone(),
            epoch: None,
            request_id: "history-packets".into(),
            offset,
            total: 2,
            manifest: "ab".repeat(32),
            records,
            fragment: None,
        }
    }

    fn receive(&mut self, packet: &[u8]) -> Result<()> {
        self.received_ms = crate::private_dm_runtime::now_ms();
        self.runtime.receive_device_packet(packet)
    }

    fn packet(&self, signer: &DeviceIdentity, message: DeviceMessage) -> Vec<u8> {
        DevicePacket::seal(signer, &self.receiver.device().moss_peer_id, message).unwrap()
    }

    fn snapshot(&mut self) -> SessionSnapshot {
        self.runtime.poll_session(&self.session).unwrap()
    }

    /// History sync after a poll, read on the clock of the last received
    /// packet. The poll dials the fixture's offline peers through real Moss,
    /// which can take seconds on a loaded runner; reading on the wall clock
    /// would then age a fresh answer past the source timeout.
    fn history_sync(&mut self) -> Option<DmHistorySyncState> {
        self.snapshot();
        self.runtime
            .session_ref(&self.session)
            .unwrap()
            .history_sync_state(self.received_ms)
    }
}

mod deletion;
mod export;
mod recovery;
mod revocation;

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn record(id: &str, body: &str) -> TextRecord {
    TextRecord {
        metadata: None,
        message_id: id.into(),
        sent_at_ms: 42,
        from_device: "Counterpart".into(),
        body: body.into(),
    }
}

fn signed_refusals(f: &mut Fixture) {
    for signer in [&f.outsider, &f.contact] {
        let batch = f.packet(
            signer,
            DeviceMessage::HistoryBatch(f.batch(0, vec![record("past", "Secret")])),
        );
        let request = f.packet(
            signer,
            DeviceMessage::HistoryRequest(HistoryRequest {
                session_id: f.session.clone(),
                request_id: "history-packets".into(),
                offset: 0,
                body_offset: 0,
            }),
        );
        assert!(f.runtime.receive_device_packet(&batch).is_err());
        assert!(f.runtime.receive_device_packet(&request).is_err());
    }
    let packet = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(f.batch(0, vec![record("past", "Secret")])),
    );
    let mut tampered: serde_json::Value = serde_json::from_slice(&packet).unwrap();
    tampered["message"]["HistoryBatch"]["records"][0]["body"] = "changed".into();
    assert!(f.receive(&serde_json::to_vec(&tampered).unwrap()).is_err());
    assert!(f.snapshot().messages.is_empty());
    f.receive(&packet).unwrap();
    assert_eq!(f.snapshot().messages[0].body, "Secret");
    assert!(f.receive(&packet).is_err());
    assert_eq!(f.snapshot().messages.len(), 1);
}

fn conflicting_and_incomplete_batches(f: &mut Fixture) {
    let first = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(f.batch(0, vec![record("past", "Secret")])),
    );
    f.receive(&first).unwrap();
    let mut bad = vec![
        f.batch(1, vec![record("past", "Forged replacement")]),
        f.batch(1, vec![]),
    ];
    let mut wrong_manifest = f.batch(1, vec![record("other", "Other")]);
    wrong_manifest.manifest = "cd".repeat(32);
    bad.push(wrong_manifest);
    for batch in bad {
        let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
        assert!(f.receive(&packet).is_err());
        assert_ne!(
            f.snapshot().history_sync,
            Some(DmHistorySyncState::Complete)
        );
        assert_eq!(f.snapshot().messages.len(), 1);
    }
    let second = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(f.batch(1, vec![record("other", "Other")])),
    );
    f.receive(&second).unwrap();
    assert_eq!(f.history_sync(), Some(DmHistorySyncState::Complete));
    let snapshot = f.snapshot();
    assert_eq!(snapshot.messages.len(), 2);
    assert_eq!(snapshot.messages[0].body, "Other");
    assert!(snapshot
        .messages
        .iter()
        .all(|message| message.retryable.is_none() && message.delivery_status.is_none()));
}

fn roster_refusals(f: &mut Fixture) {
    let old = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(f.batch(0, vec![record("past", "Secret")])),
    );
    let roster = f
        .receiver
        .roster()
        .extend(f.outsider.device().clone(), &f.receiver.key())
        .unwrap();
    adopt(&mut f.receiver, roster.clone());
    adopt(&mut f.outsider, roster);
    let unadmitted = f.packet(
        &f.outsider,
        DeviceMessage::HistoryBatch(f.batch(0, vec![record("past", "Secret")])),
    );
    assert!(f.receive(&old).is_err());
    assert!(f.receive(&unadmitted).is_err());
    assert!(f.snapshot().messages.is_empty());
}

fn fragments_survive_restart_and_refuse_wrong_continuations(f: &mut Fixture) {
    let mut batch = f.batch(0, Vec::new());
    batch.total = 1;
    batch.fragment = Some(TextFragment {
        record: record("part", "abc"),
        body_offset: 0,
        body_length: 6,
    });
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch.clone()));
    f.receive(&packet).unwrap();
    assert!(f.snapshot().messages.is_empty());
    f.runtime.rehydrate();
    assert!(f.receive(&packet).is_err());
    assert!(f.snapshot().messages.is_empty());
    let mut bad = batch.clone();
    bad.fragment.as_mut().unwrap().body_offset = 99;
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(bad));
    assert!(f.receive(&packet).is_err());
    batch.fragment = Some(TextFragment {
        record: record("part", "def"),
        body_offset: 3,
        body_length: 6,
    });
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
    f.receive(&packet).unwrap();
    assert_eq!(f.history_sync(), Some(DmHistorySyncState::Complete));
    let snapshot = f.snapshot();
    assert_eq!(snapshot.messages.len(), 1);
    assert_eq!(snapshot.messages[0].body, "abcdef");
}

#[test]
fn signed_history_boundary_refuses_outsiders_tampering_conflicts_and_stale_rosters() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::devices::history::packet_tests::history_packet_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Independent installation worker, invoked by the signed boundary test."]
fn history_packet_process() {
    export::frozen_metadata_survives_a_recovery_checkpoint(&mut Fixture::new());
    signed_refusals(&mut Fixture::new());
    conflicting_and_incomplete_batches(&mut Fixture::new());
    roster_refusals(&mut Fixture::new());
    fragments_survive_restart_and_refuse_wrong_continuations(&mut Fixture::new());
    deletion::authenticated_legacy_history_can_be_erased_across_own_devices(&mut Fixture::new());
    deletion::legacy_source_preserves_verified_live_origins(&mut Fixture::new());
}
