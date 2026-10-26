use super::*;

#[test]
fn refused_staged_receive_can_retry_without_consuming_the_live_ratchet() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let package = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&package).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();
    let ciphertext = alice.encrypt(b"retain original accepted content").unwrap();
    let signer = alice.signer_public();

    let staged = bob
        .stage_decrypt_checked(&ciphertext, |body, actual| {
            assert_eq!(body, b"retain original accepted content");
            assert_eq!(actual, signer);
            Ok(())
        })
        .unwrap();
    assert_eq!(staged.body, b"retain original accepted content");
    drop(staged);

    let accepted = bob
        .stage_decrypt_checked(&ciphertext, |_, actual| {
            assert_eq!(actual, signer);
            Ok(())
        })
        .unwrap();
    assert_eq!(accepted.signer, signer);
    bob = accepted.next;
    assert!(bob.decrypt(&ciphertext).is_err());
    let next = alice.encrypt(b"live traffic still works").unwrap();
    assert_eq!(bob.decrypt(&next).unwrap(), b"live traffic still works");
}
