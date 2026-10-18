use super::*;
use crate::message_deletion::MessageOrigin;
use crate::mls_crypto::MlsSessionCrypto;
use ed25519_dalek::SigningKey;

fn offered_invite(target: &str) -> (DmOffer, SigningKey) {
    let key = SigningKey::from_bytes(&[4; 32]);
    let peer = hex::encode(key.verifying_key().as_bytes());
    let mut crypto = MlsSessionCrypto::new("owner").unwrap();
    crypto.create_group().unwrap();
    let raw = format!(
        "mosh://invite?mesh=mesh&session=session&moss={peer}&target={target}#fp={}",
        crypto.fingerprint()
    );
    let uri =
        crate::private_dm_runtime::invite_ownership::sign_invite(&raw, &key, &crypto).unwrap();
    (
        DmOffers::mint("Paid sender".into(), peer, target.into(), uri),
        key,
    )
}

#[test]
fn only_the_signed_offer_name_and_invite_can_represent_a_paid_author() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    drain_received_messages();
    let native = Arc::new(MossFfiRuntime::load_default().unwrap());
    let mut runtime = ChannelRuntime::from_shared(native, temp_store(), None);
    let snapshot = runtime
        .join(JoinChannelRequest {
            name: "plus-offers".into(),
            display_name: "Receiver".into(),
            listen_port: 0,
            static_peer: None,
        })
        .unwrap();
    let (offer, key) = offered_invite(&snapshot.device_fingerprint);
    let origin = MessageOrigin::sign(
        "channel-offer:plus-offers",
        &offer.offer_id,
        &offer.signing_bytes().unwrap(),
        &key,
        None,
    )
    .unwrap();
    let original = serde_json::to_value(ChannelBlobEnvelope::DmOffer {
        offer: offer.clone(),
        origin: Some(origin),
    })
    .unwrap();
    for changed in [false, true] {
        let mut wire = original.clone();
        if changed {
            wire["offer"]["from_device"] = "Forged name".into();
        }
        wire["offer"]["authenticated"] = true.into();
        let received = runtime
            .channel_mut("plus-offers")
            .unwrap()
            .handle_blob(serde_json::to_vec(&wire).unwrap());
        if changed {
            assert!(received.is_err());
            assert!(runtime.poll("plus-offers").unwrap().dm_offers.is_empty());
            continue;
        }
        received.unwrap();
        let saved = runtime.poll("plus-offers").unwrap().dm_offers.remove(0);
        assert_eq!(saved.authenticated, Some(true));
        runtime
            .dismiss_dm_offer("plus-offers", &offer.offer_id)
            .unwrap();
    }
    let mut legacy = original.clone();
    legacy.as_object_mut().unwrap().remove("origin");
    legacy["offer"]["from_device"] = "Unverified legacy".into();
    legacy["offer"]["authenticated"] = true.into();
    runtime
        .channel_mut("plus-offers")
        .unwrap()
        .handle_blob(serde_json::to_vec(&legacy).unwrap())
        .unwrap();
    assert_eq!(
        runtime.poll("plus-offers").unwrap().dm_offers[0].authenticated,
        None
    );
    runtime
        .channel_mut("plus-offers")
        .unwrap()
        .handle_blob(serde_json::to_vec(&original).unwrap())
        .unwrap();
    let offers = runtime.poll("plus-offers").unwrap().dm_offers;
    assert_eq!(offers.len(), 1);
    assert_eq!(offers[0].from_device, "Paid sender");
    assert_eq!(offers[0].authenticated, Some(true));
}
