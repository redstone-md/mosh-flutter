use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::Fixture;

struct Source {
    fixture: Fixture,
    scope: GroupScope,
    frame: HistoryFrame,
}

impl Source {
    fn new() -> Self {
        Self::from_fixture(Fixture::new())
    }

    fn from_fixture(mut fixture: Fixture) -> Self {
        let (_, sender) = super::super::import::tests::retained(&mut fixture, "first publication");
        let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
        let scope = session.own_history_scope().unwrap();
        let frame = HistoryFrame {
            version: 1,
            conversation: session.deletions.context.clone(),
            mesh_id: session.mesh_id.clone(),
            channel: session.control_channel.clone(),
            sender_key: sender.peer_id,
            recipient_key: None,
            request_id: "61".repeat(16),
            round: 1,
            payload_b64: String::new(),
            signature: String::new(),
        };
        Self {
            fixture,
            scope,
            frame,
        }
    }

    fn answer(
        &mut self,
        pull: Option<HistoryPull>,
    ) -> Result<HistoryMessage<GroupRecord>, PrivateGroupError> {
        self.fixture
            .runtime
            .groups
            .get_mut(&self.fixture.id)
            .unwrap()
            .history_answer(&self.frame, &self.scope, pull, None)
            .map(|result| result.0)
    }

    fn offer(&mut self) -> Result<(String, usize, String), PrivateGroupError> {
        let HistoryMessage::Offer {
            manifest,
            total,
            deletion_digest,
        } = self.answer(None)?
        else {
            panic!("expected authenticated group Offer");
        };
        Ok((manifest, total, deletion_digest))
    }

    fn publish(&mut self, text: &str) {
        self.fixture
            .runtime
            .send(&self.fixture.id, text.into())
            .unwrap();
    }
}

#[test]
fn unchanged_group_offers_do_not_rescan_the_encrypted_history() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut source = Source::new();
    let offer = source.offer().unwrap();
    let fault = source.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert_eq!(source.offer().unwrap(), offer);
    drop(fault);
    source.publish("new durable publication");
    let next = source.offer().unwrap();
    assert_eq!(next.1, 2);
    assert_ne!(next.0, offer.0);
}

#[test]
fn a_frozen_journal_does_not_rescan_new_history_or_skip_recipient_rechecks() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut source = Source::new();
    let (manifest, _, deletion_digest) = source.offer().unwrap();
    let pull = HistoryPull {
        manifest,
        offset: 0,
        fragment_offset: 0,
        deletion_digest,
        journal: true,
        journal_after: None,
    };
    assert!(matches!(
        source.answer(Some(pull.clone())).unwrap(),
        HistoryMessage::Journal { .. }
    ));
    source.publish("arrives after frozen export");
    let fault = source.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(matches!(
        source.answer(Some(pull.clone())).unwrap(),
        HistoryMessage::Journal { .. }
    ));
    source.frame.sender_key = "62".repeat(32);
    assert!(source.answer(Some(pull)).is_err());
    drop(fault);
}

#[test]
fn deletion_and_a_native_membership_change_invalidate_cached_offers() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut source = Source::new();
    let first = source.offer().unwrap();
    let mut newcomer = MlsSessionCrypto::new("new member").unwrap();
    let package = newcomer.key_package_bytes().unwrap();
    let session = source
        .fixture
        .runtime
        .groups
        .get_mut(&source.fixture.id)
        .unwrap();
    session
        .admit_history_member(
            "new member".into(),
            &package,
            None,
            session.crypto.fingerprint(),
        )
        .unwrap();
    assert!(
        source.offer().is_err(),
        "old membership head must not reuse an Offer"
    );
    source.scope = source
        .fixture
        .runtime
        .groups
        .get_mut(&source.fixture.id)
        .unwrap()
        .own_history_scope()
        .unwrap();
    let fault = source.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(
        source.offer().is_err(),
        "new head requires its own manifest"
    );
    drop(fault);
    assert_eq!(source.offer().unwrap().1, first.1);
    let message = source
        .fixture
        .runtime
        .poll(&source.fixture.id)
        .unwrap()
        .messages[0]
        .message_id
        .clone()
        .unwrap();
    source
        .fixture
        .runtime
        .delete_messages(
            &source.fixture.id,
            &[message],
            crate::message_deletion::DeleteScope::ForEveryone,
        )
        .unwrap();
    let fault = source.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(
        source.offer().is_err(),
        "deletion must invalidate the manifest"
    );
    drop(fault);
    assert_eq!(source.offer().unwrap().1, 0);
}

#[test]
fn verified_roster_updates_invalidate_offers_and_revocation_blocks_cached_access() {
    use ed25519_dalek::SigningKey;
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let root = SigningKey::from_bytes(&[94; 32]);
    let org = hex::encode(root.verifying_key().to_bytes());
    fixture.id = fixture
        .runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "org source".into(),
            listen_port: 0,
            static_peer: None,
            org_pubkey: Some(org.clone()),
        })
        .unwrap()
        .group_id;
    let own = fixture
        .runtime
        .groups
        .get(&fixture.id)
        .unwrap()
        .device_fingerprint
        .clone();
    let save_roster = |version, member: bool| {
        let mut roster = serde_json::json!({"org_pubkey":org, "org_name":"History",
            "version":version, "members": if member {vec![serde_json::json!({
                "moss_peer_id":own, "name":"source", "role":"admin"})]} else {Vec::new()} });
        let bytes = org_roster::sign_roster(&mut roster, &root).unwrap();
        fixture.store.put_org_roster(&org, &bytes).unwrap();
    };
    save_roster(1, true);
    let mut source = Source::from_fixture(fixture);
    let first = source.offer().unwrap();
    let mut next = serde_json::json!({"org_pubkey":org, "org_name":"History", "version":2,
        "members":[{"moss_peer_id":own,"name":"source renamed","role":"admin"}]});
    let bytes = org_roster::sign_roster(&mut next, &root).unwrap();
    source.fixture.store.put_org_roster(&org, &bytes).unwrap();
    assert!(
        source.offer().is_err(),
        "old roster head must not reuse an Offer"
    );
    source.scope = source
        .fixture
        .runtime
        .groups
        .get_mut(&source.fixture.id)
        .unwrap()
        .own_history_scope()
        .unwrap();
    let fault = source.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(
        source.offer().is_err(),
        "new authority requires a new manifest"
    );
    drop(fault);
    assert_eq!(source.offer().unwrap().1, first.1);
    next["version"] = 3.into();
    next["members"] = serde_json::json!([]);
    let bytes = org_roster::sign_roster(&mut next, &root).unwrap();
    source.fixture.store.put_org_roster(&org, &bytes).unwrap();
    assert!(
        source.offer().is_err(),
        "revoked member cannot receive a cached Offer"
    );
}
