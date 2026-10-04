use super::*;

fn context() -> OrgContext<'static> {
    OrgContext {
        org_pubkey: "org",
        mesh_id: "mesh",
        channel_kind: "group-data/id",
    }
}

fn identity() -> SigningKey {
    SigningKey::from_bytes(&[9; 32])
}

fn proof() -> SenderProof {
    SenderProof::sign(
        &identity(),
        &MlsSessionCrypto::new("member").unwrap(),
        &context(),
        b"message".to_vec(),
    )
    .unwrap()
}

fn signed_bound(mut transform: impl FnMut(&mut BoundPayload)) -> SenderProof {
    let crypto = MlsSessionCrypto::new("member").unwrap();
    let mut bound = BoundPayload {
        version: 1,
        mls_signer: crypto.signer_public(),
        payload_b64: crate::conversation::encode(b"message"),
    };
    transform(&mut bound);
    let bytes = serde_json::to_vec(&bound).unwrap();
    SenderProof {
        identity: org_envelope::sign(&identity(), &context(), &bytes),
        mls_signature: crypto
            .sign_sender_proof(&org_envelope::signing_input(&context(), &bytes))
            .unwrap(),
    }
}

#[test]
fn proof_binds_both_full_keys_and_the_exact_payload_to_its_context() {
    let proof = proof();
    let proof: SenderProof = serde_json::from_slice(&serde_json::to_vec(&proof).unwrap()).unwrap();
    let verified = proof.verify(&context()).unwrap();
    assert_eq!(
        verified.peer_id,
        hex::encode(identity().verifying_key().to_bytes())
    );
    assert_eq!(verified.mls_signer.len(), 32);
    assert_eq!(verified.payload, b"message");
    for other in [
        OrgContext {
            org_pubkey: "other",
            ..context()
        },
        OrgContext {
            mesh_id: "other",
            ..context()
        },
        OrgContext {
            channel_kind: "group-control/id",
            ..context()
        },
    ] {
        assert!(proof.verify(&other).is_err());
    }
}

#[test]
fn malformed_identity_payload_encoding_is_rejected_at_the_wire_boundary() {
    let mut wire = serde_json::to_value(proof()).unwrap();
    wire["identity"]["payload_b64"] = serde_json::json!("invalid base64");
    assert!(serde_json::from_value::<SenderProof>(wire).is_err());
}

#[test]
fn copying_a_moss_signature_does_not_authorize_another_mls_key() {
    let mut proof = proof();
    let mut bound: BoundPayload = serde_json::from_slice(&proof.identity.payload).unwrap();
    bound.mls_signer = MlsSessionCrypto::new("attacker").unwrap().signer_public();
    proof.identity = org_envelope::sign(
        &identity(),
        &context(),
        &serde_json::to_vec(&bound).unwrap(),
    );
    assert!(proof.verify(&context()).is_err());
}

#[test]
fn changed_moss_and_mls_signatures_are_rejected() {
    let mut forged = proof();
    forged.identity.sig[0] ^= 1;
    assert!(forged.verify(&context()).is_err());
    let mut forged = proof();
    forged.mls_signature[0] ^= 1;
    assert!(forged.verify(&context()).is_err());
    forged.mls_signature.clear();
    assert!(forged.verify(&context()).is_err());
}

#[test]
fn signed_unsupported_versions_invalid_keys_and_bad_encoding_are_rejected() {
    assert!(signed_bound(|bound| bound.version = 2)
        .verify(&context())
        .is_err());
    assert!(signed_bound(|bound| bound.mls_signer.truncate(31))
        .verify(&context())
        .is_err());
    assert!(signed_bound(|bound| bound.mls_signer = vec![0; 32])
        .verify(&context())
        .is_err());
    assert!(
        signed_bound(|bound| bound.payload_b64 = "not base64".into())
            .verify(&context())
            .is_err()
    );
    let mut malformed = proof();
    malformed.identity = org_envelope::sign(&identity(), &context(), b"not JSON");
    assert!(malformed.verify(&context()).is_err());
}
