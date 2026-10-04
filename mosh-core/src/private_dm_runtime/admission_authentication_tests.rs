use super::*;
use crate::private_dm_runtime::state_tests::{invite, memory_pair};
use ed25519_dalek::SigningKey;

fn peer(seed: u8) -> String {
    hex::encode(
        SigningKey::from_bytes(&[seed; 32])
            .verifying_key()
            .to_bytes(),
    )
}

fn signed_package(
    session: &PrivateDmSession,
    seed: u8,
    signer: &MlsSessionCrypto,
    package: &[u8],
) -> Vec<u8> {
    let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
        session_id: session.session_id.clone(),
        participant_id: "invitee".into(),
        from_device: "claimed name".into(),
        key_package_b64: encode(package),
        moss_peer_id: Some(peer(seed)),
    })
    .unwrap();
    let proof = SenderProof::sign(
        &SigningKey::from_bytes(&[seed; 32]),
        signer,
        &crate::org_envelope::OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: "dm-key-package-v1",
        },
        payload,
    )
    .unwrap();
    serde_json::to_vec(&ControlEnvelope::AuthenticatedKeyPackage {
        session_id: session.session_id.clone(),
        proof_b64: encode(&serde_json::to_vec(&proof).unwrap()),
    })
    .unwrap()
}

#[test]
fn the_target_proves_both_keys_and_rejected_packages_do_not_change_membership_or_names() {
    let (_, mut alice, _) = memory_pair();
    let invitation = invite(&mut alice);
    let session = alice.sessions.get_mut(&invitation.session_id).unwrap();
    let mut uri = url::Url::parse(&invitation.invite_uri).unwrap();
    uri.query_pairs_mut().append_pair("target", &peer(7));
    session.invite_uri = Some(uri.into());
    let mut target = MlsSessionCrypto::new("Mia").unwrap();
    let package = target.key_package_bytes().unwrap();
    let mut attacker = MlsSessionCrypto::new("Mallory").unwrap();
    let attacker_package = attacker.key_package_bytes().unwrap();
    for forged in [
        signed_package(session, 8, &attacker, &attacker_package),
        signed_package(session, 7, &target, &attacker_package),
    ] {
        assert!(session.handle_control(forged).is_err());
        assert_eq!(session.crypto.member_count(), 1);
        assert!(!session.peer_joined);
        assert!(session.peer_display_name.is_none());
        assert!(session.peer_moss_id.is_none());
    }
    let genuine = signed_package(session, 7, &target, &package);
    assert_eq!(
        admission_key_package(&genuine, &session.mesh_id).unwrap(),
        Some(package)
    );
    session.handle_control(genuine.clone()).unwrap();
    session.handle_control(genuine).unwrap();
    assert_eq!(session.crypto.member_count(), 2);
    assert_eq!(session.peer_display_name.as_deref(), Some("Mia"));
    assert_eq!(session.peer_moss_id, Some(peer(7)));
}

#[test]
fn an_admission_proof_does_not_accept_another_control_kind() {
    let (_, mut alice, _) = memory_pair();
    let invitation = invite(&mut alice);
    let session = alice.sessions.get_mut(&invitation.session_id).unwrap();
    let signer = MlsSessionCrypto::new("Mia").unwrap();
    let proof = SenderProof::sign(
        &SigningKey::from_bytes(&[7; 32]),
        &signer,
        &crate::org_envelope::OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: "dm-key-package-v1",
        },
        serde_json::to_vec(&ControlEnvelope::Hello {
            session_id: invitation.session_id,
            participant_id: "invitee".into(),
            from_device: "Mia".into(),
            hello_ciphertext_b64: "".into(),
        })
        .unwrap(),
    )
    .unwrap();
    assert!(session
        .accept_authenticated_key_package(&encode(&serde_json::to_vec(&proof).unwrap()))
        .is_err());
    assert_eq!(session.crypto.member_count(), 1);
}
