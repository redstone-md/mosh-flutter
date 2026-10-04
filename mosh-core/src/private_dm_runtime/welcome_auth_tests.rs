use super::*;
use crate::private_dm_runtime::state_tests::{accept, invite, memory_pair};

fn welcome(id: &str, outcome: &crate::mls_crypto::AddOutcome, name: &str) -> Vec<u8> {
    serde_json::to_vec(&ControlEnvelope::Welcome {
        session_id: id.into(),
        participant_id: "creator".into(),
        from_device: name.into(),
        welcome_b64: encode(&outcome.welcome_bytes),
        ratchet_tree_b64: encode(&outcome.tree_bytes),
        moss_peer_id: Some("c".repeat(64)),
    })
    .unwrap()
}

#[test]
fn wrong_inviter_welcome_is_rejected_without_consuming_the_legitimate_key_package() {
    let (_, mut alice, mut bob) = memory_pair();
    let invitation = invite(&mut alice);
    accept(&mut bob, &invitation);
    let session = bob.sessions.get_mut(&invitation.session_id).unwrap();
    let ControlEnvelope::KeyPackage {
        key_package_b64, ..
    } = decode_json(session.pending_key_package.as_ref().unwrap()).unwrap()
    else {
        panic!("KeyPackage");
    };
    let package = decode(&key_package_b64).unwrap();
    let before = session.crypto.snapshot();
    let mut attacker = MlsSessionCrypto::new("Mallory").unwrap();
    attacker.create_group().unwrap();
    let forged = attacker.add_members(&[&package]).unwrap();
    assert!(session
        .handle_control(welcome(&invitation.session_id, &forged, "Alice"))
        .is_err());
    assert!(!session.crypto.is_ready());
    assert_eq!(
        session.crypto.snapshot(),
        before,
        "a rejected Welcome must preserve admission material"
    );
    let genuine = alice
        .sessions
        .get_mut(&invitation.session_id)
        .unwrap()
        .crypto
        .add_members(&[&package])
        .unwrap();
    session
        .handle_control(welcome(&invitation.session_id, &genuine, "Alice"))
        .unwrap();
    assert!(session.crypto.is_ready());
}

#[test]
fn an_offer_target_cannot_be_impersonated_by_an_unsigned_key_package() {
    let (_, mut alice, _) = memory_pair();
    let invitation = invite(&mut alice);
    let session = alice.sessions.get_mut(&invitation.session_id).unwrap();
    let mut uri = url::Url::parse(&invitation.invite_uri).unwrap();
    uri.query_pairs_mut().append_pair(
        "target",
        &hex::encode(
            ed25519_dalek::SigningKey::from_bytes(&[7; 32])
                .verifying_key()
                .to_bytes(),
        ),
    );
    session.invite_uri = Some(uri.into());
    let mut attacker = MlsSessionCrypto::new("intended target").unwrap();
    let package = ControlEnvelope::KeyPackage {
        session_id: invitation.session_id,
        participant_id: "attacker".into(),
        from_device: "intended target".into(),
        key_package_b64: encode(&attacker.key_package_bytes().unwrap()),
        moss_peer_id: Some("a".repeat(64)),
    };
    let _ = session.handle_control(serde_json::to_vec(&package).unwrap());
    assert_eq!(
        session.crypto.member_count(),
        1,
        "only the offered target may join this DM"
    );
}
