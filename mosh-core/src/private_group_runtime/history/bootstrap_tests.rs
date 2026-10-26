use super::*;
use crate::conversation::recovery::{fragment::fragment, wire::HistoryPull};
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::Fixture;
use crate::sender_auth::SenderProof;
use ed25519_dalek::SigningKey;

#[test]
fn an_unknown_signed_leaf_cannot_offer_or_request_content_before_native_membership() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let prior = session.crypto.history_context().unwrap();
    let identity = SigningKey::from_bytes(&[93; 32]);
    let mut unknown = MlsSessionCrypto::new("not admitted").unwrap();
    unknown.create_group().unwrap();
    let proof = SenderProof::sign(
        &identity,
        &unknown,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        b"original key binding".to_vec(),
    )
    .unwrap();
    let bytes = serde_json::to_vec(&proof).unwrap();
    let mut scope = serde_json::to_value(session.own_history_scope().unwrap()).unwrap();
    scope["head"]["context"]["epoch"] = (prior.epoch + 1).into();
    scope["head"]["context"]["hash"] = "71".repeat(32).into();
    scope["membership"]["checkpoint"]["mls_key"] = hex::encode(unknown.signer_public()).into();
    scope["membership"]["checkpoint"]["moss_key"] =
        hex::encode(identity.verifying_key().to_bytes()).into();
    scope["membership"]["checkpoint"]["binding_hash"] = hex::encode(Sha256::digest(&bytes)).into();
    scope["membership"]["original_binding_proof_b64"] = encode(&bytes).into();
    let mut body = GroupBody {
        scope: serde_json::from_value(scope).unwrap(),
        message: HistoryMessage::Probe,
        evidence: None,
        partial_digest: None,
        erased_fragment: false,
    };
    assert!(session.history_carrier_member(&body).is_ok());
    let target = body.scope.head.clone();
    body.message = HistoryMessage::Unavailable;
    body.evidence = Some(EvidenceMessage::Page {
        have: prior.clone(),
        target: target.clone(),
        fragment: fragment(b"not a native commit", 0).unwrap(),
    });
    assert!(session.history_carrier_member(&body).is_ok());
    body.evidence = Some(EvidenceMessage::Pull {
        have: prior.clone(),
        target,
        offset: 0,
    });
    assert!(session.history_carrier_member(&body).is_err());
    body.evidence = None;
    for message in [
        HistoryMessage::Unavailable,
        HistoryMessage::Offer {
            manifest: "24".repeat(32),
            total: 1,
            deletion_digest: "25".repeat(32),
        },
        HistoryMessage::Page {
            manifest: "24".repeat(32),
            total: 1,
            offset: 0,
            records: Vec::new(),
            fragment: None,
        },
        HistoryMessage::Pull(HistoryPull {
            manifest: "24".repeat(32),
            offset: 0,
            fragment_offset: 0,
            deletion_digest: "25".repeat(32),
            journal: false,
            journal_after: None,
        }),
    ] {
        body.message = message;
        assert!(session.history_carrier_member(&body).is_err());
    }
    assert_eq!(session.crypto.history_context().unwrap(), prior);
    assert!(session.messages.is_empty());
}
