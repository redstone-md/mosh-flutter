use super::*;
use crate::moss_ffi::{
    drain_received_messages, MossFfiRuntime, MossReceivedMessage, MOSS_TEST_LOCK,
};
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    store: Arc<Persistence>,
    attachments: Arc<AttachmentStore>,
    moss: Arc<MossFfiRuntime>,
    runtime: PrivateDmRuntime,
    session: String,
    peer: MlsSessionCrypto,
    _directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("mosh-dm-coherent-write");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [39; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        let mut runtime =
            PrivateDmRuntime::from_shared(moss.clone(), attachments.clone(), Some(store.clone()));
        let session = runtime
            .create_invite(StartSessionRequest {
                display_name: "Alice".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap()
            .session_id;
        let mut fixture = Self {
            store,
            attachments,
            moss,
            runtime,
            session,
            peer: MlsSessionCrypto::new("Bob").unwrap(),
            _directory: directory,
        };
        fixture.handshake();
        fixture
    }

    fn deliver(&self, envelope: &ControlEnvelope) {
        crate::inbox::deliver(MossReceivedMessage {
            channel: control_channel(&self.session),
            payload: serde_json::to_vec(envelope).unwrap(),
        });
    }

    fn handshake(&mut self) {
        let key_package = self.peer.key_package_bytes().unwrap();
        self.deliver(&ControlEnvelope::KeyPackage {
            session_id: self.session.clone(),
            participant_id: "peer-participant".into(),
            from_device: "Bob".into(),
            moss_peer_id: None,
            key_package_b64: encode(&key_package),
        });
        self.runtime.poll_session(&self.session).unwrap();
        self.join_pending_welcome();
        let hello = self.peer.encrypt(b"peer-address").unwrap();
        self.deliver(&ControlEnvelope::Hello {
            session_id: self.session.clone(),
            participant_id: "peer-participant".into(),
            from_device: "Bob".into(),
            hello_ciphertext_b64: encode(&hello),
        });
        assert_eq!(
            self.runtime.poll_session(&self.session).unwrap().state,
            DmSessionState::Connected
        );
    }

    fn join_pending_welcome(&mut self) {
        let welcome = self
            .runtime
            .session_ref(&self.session)
            .unwrap()
            .pending_welcome
            .as_ref()
            .unwrap();
        let ControlEnvelope::Welcome {
            welcome_b64,
            ratchet_tree_b64,
            ..
        } = decode_json(welcome).unwrap()
        else {
            panic!("Alice publishes a Welcome")
        };
        self.peer
            .join_welcome(
                &decode(&welcome_b64).unwrap(),
                &decode(&ratchet_tree_b64).unwrap(),
            )
            .unwrap();
    }

    fn receipt(&mut self, message: &str) -> ControlEnvelope {
        let body = serde_json::to_vec(&ReadReceiptBody {
            message_id: message.into(),
        })
        .unwrap();
        let ciphertext = self.peer.encrypt(&body).unwrap();
        ControlEnvelope::ReadReceipt {
            session_id: self.session.clone(),
            participant_id: "peer-participant".into(),
            receipt_ciphertext_b64: encode(&ciphertext),
        }
    }

    fn restart(&mut self) {
        self.runtime = PrivateDmRuntime::from_shared(
            self.moss.clone(),
            self.attachments.clone(),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }

    fn read(&mut self) -> Option<bool> {
        self.runtime.poll_session(&self.session).unwrap().messages[0].read
    }
}

#[test]
fn refused_read_metadata_does_not_consume_its_replay_after_restart() {
    // Facade tests start a permanent DM service sharing this process's inbox.
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::write_coherence_tests::read_metadata_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Independent DM inbox, invoked by the read metadata regression."]
fn read_metadata_process() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let config = std::env::temp_dir().join(format!(
        "mosh-receipts-toggle-{}-shared",
        std::process::id()
    ));
    let _ = crate::api::shared_runtime::set_app_data_dir(config.to_string_lossy().into_owned());
    let mut fixture = Fixture::new();
    let previous_receipts = fixture.runtime.read_receipts_enabled();
    fixture.runtime.set_read_receipts_enabled(true).unwrap();
    let sent = fixture
        .runtime
        .send_message(&fixture.session, "authenticated read".into())
        .unwrap();
    let receipt = fixture.receipt(&sent.message_id);
    let fault = fixture.store.refuse_record_writes(DM_HISTORY);
    fixture.deliver(&receipt);
    assert_eq!(
        fixture.read(),
        Some(true),
        "the live view accepts the authenticated receipt"
    );
    fixture.restart();
    drop(fault);
    // Repair and restart without giving the refused write another attempt.
    fixture.restart();
    fixture.deliver(&receipt);
    let restored_read = fixture.read();
    fixture
        .runtime
        .set_read_receipts_enabled(previous_receipts)
        .unwrap();
    assert_eq!(
        restored_read,
        Some(true),
        "the saved MLS ratchet must retain a refused receipt's replay"
    );
}

#[test]
fn queued_invitee_keeps_its_record_provisional_until_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    drain_received_messages();
    let directory = TempDirectory::new("mosh-dm-provisional-write");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [39; 32]).unwrap(),
    );
    let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    let mut runtime = PrivateDmRuntime::from_shared(moss, attachments, Some(store.clone()));
    let mut inviter = MlsSessionCrypto::new("Alice").unwrap();
    inviter.create_group().unwrap();
    let invite = build_invite_uri(
        "pending-mesh",
        "pending-session",
        &inviter.fingerprint(),
        None,
    );
    let joined = runtime
        .accept_invite(AcceptInviteRequest {
            invite_uri: invite,
            display_name: "Bob".into(),
            listen_port: 0,
            static_peer: None,
        })
        .unwrap();
    let sent = runtime
        .send_message(&joined.session_id, "before Welcome".into())
        .unwrap();
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
    assert!(store.list_sessions().unwrap().is_empty());
    assert!(store
        .get_mls_snapshot(&joined.session_id)
        .unwrap()
        .is_some());
}
