use super::*;
use crate::private_group_runtime::history::CurrentHead;

struct Replay {
    fixture: Fixture,
    prior: crate::mls_crypto::MlsHistoryContext,
    next: CurrentHead,
    bytes: Vec<u8>,
}

impl Replay {
    fn new() -> Self {
        let mut fixture = Fixture::empty();
        let mut admin = MlsSessionCrypto::new("Alice").unwrap();
        admin.create_group().unwrap();
        let invite = build_invite_uri(
            "evidence-replay",
            "evidence-replay",
            &admin.fingerprint(),
            &None,
        );
        fixture.join(&invite, "Bob");
        fixture.deliver_welcome(&mut admin);
        assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 2);
        let prior = admin.history_context().unwrap();
        let previous = admin.receive_candidate().unwrap();
        let mut carol = MlsSessionCrypto::new("Carol").unwrap();
        let outcome = admin
            .add_members(&[&carol.key_package_bytes().unwrap()])
            .unwrap();
        let context = admin.history_context().unwrap();
        let bytes = serde_json::to_vec(&serde_json::json!({
            "prior": prior, "next": context,
            "original_author_mls_key": hex::encode(admin.signer_public()),
            "original_commit_b64": encode(&outcome.commit_bytes),
            "previous_member_keys": previous.member_signers(), "next_member_keys": admin.member_signers(),
            "self_removed": false, "original_signed_transition": null,
        })).unwrap();
        Self {
            fixture,
            prior,
            next: CurrentHead {
                context,
                org_roster_version: None,
                org_roster_hash: None,
            },
            bytes,
        }
    }

    fn install(&mut self, bytes: &[u8]) -> Result<(), PrivateGroupError> {
        self.fixture
            .runtime
            .groups
            .get_mut(&self.fixture.id)
            .unwrap()
            .install_transition_evidence(&self.prior, &self.next, bytes, "partial\u{1}state")
    }
}

#[test]
fn refused_membership_evidence_preserves_own_state_and_partial_until_exact_retry() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut replay = Replay::new();
    replay
        .fixture
        .store
        .save_recovery("partial\u{1}state", &"durable original fragment")
        .unwrap();
    let bytes = replay.bytes.clone();
    let fault = replay.fixture.store.refuse_group_snapshot_writes();
    assert!(matches!(
        replay.install(&bytes),
        Err(PrivateGroupError::Persistence(_))
    ));
    assert_eq!(
        replay
            .fixture
            .runtime
            .groups
            .get(&replay.fixture.id)
            .unwrap()
            .crypto
            .history_context()
            .unwrap(),
        replay.prior
    );
    assert!(replay
        .fixture
        .store
        .recovery_state::<String>("partial\u{1}state")
        .unwrap()
        .is_some());
    drop(fault);
    replay.install(&bytes).unwrap();
    assert!(replay
        .fixture
        .store
        .recovery_state::<String>("partial\u{1}state")
        .unwrap()
        .is_none());
    replay.fixture.restart();
    assert_eq!(
        replay
            .fixture
            .runtime
            .poll(&replay.fixture.id)
            .unwrap()
            .member_count,
        3
    );
    assert_eq!(
        replay
            .fixture
            .runtime
            .groups
            .get(&replay.fixture.id)
            .unwrap()
            .crypto
            .history_context()
            .unwrap(),
        replay.next.context
    );
}

#[test]
fn asserted_transition_or_target_context_cannot_override_actual_native_commit() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut replay = Replay::new();
    let mut forged: serde_json::Value = serde_json::from_slice(&replay.bytes).unwrap();
    forged["next"]["hash"] = "00".repeat(32).into();
    assert!(replay
        .install(&serde_json::to_vec(&forged).unwrap())
        .is_err());
    assert_eq!(
        replay
            .fixture
            .runtime
            .groups
            .get(&replay.fixture.id)
            .unwrap()
            .crypto
            .history_context()
            .unwrap(),
        replay.prior
    );
    replay.next.context.hash = "11".repeat(32);
    assert!(replay.install(&replay.bytes.clone()).is_err());
    assert_eq!(
        replay
            .fixture
            .runtime
            .groups
            .get(&replay.fixture.id)
            .unwrap()
            .crypto
            .history_context()
            .unwrap(),
        replay.prior
    );
}

#[test]
fn an_issuer_removal_is_not_installed_before_its_own_snapshot_and_public_interval() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut member, _) = super::history::member(&mut fixture);
    let proposal = member.leave_proposal_bytes().unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let payload = serde_json::to_vec(&ControlEnvelope::SelfRemove {
        group_id: fixture.id.clone(),
        from_fingerprint: member.fingerprint(),
        proposal_b64: encode(&proposal),
        name_state_proof_b64: None,
    })
    .unwrap();
    let prior = session.crypto.history_context().unwrap();
    let fault = fixture.store.refuse_group_snapshot_writes();
    assert!(matches!(
        session.handle_control(payload.clone(), None),
        Err(PrivateGroupError::Persistence(_))
    ));
    assert_eq!(session.crypto.history_context().unwrap(), prior);
    assert_eq!(session.crypto.member_count(), 2);
    drop(fault);
    session.handle_control(payload, None).unwrap();
    assert_eq!(session.crypto.member_count(), 1);
    use sha2::{Digest, Sha256};
    let key = format!(
        "group/{}/transition/{:020}",
        hex::encode(Sha256::digest(fixture.id.as_bytes())),
        prior.epoch
    );
    let transition = fixture
        .store
        .group_history_evidence::<serde_json::Value>(&key)
        .unwrap()
        .unwrap();
    assert_eq!(
        transition["previous_member_keys"].as_array().unwrap().len(),
        2
    );
    assert_eq!(transition["next_member_keys"].as_array().unwrap().len(), 1);
    fixture.restart();
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 1);
}
