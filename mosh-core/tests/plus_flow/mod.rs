use super::*;
use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::PartiallyBlindKeyPairSha384PSSDeterministic as KeyPair;
use blind_rsa_signatures::pbrsa::PartiallyBlindSecretKeySha384PSSDeterministic as SecretKey;

fn activate(peer: &mut Peer, key: &KeyPair) {
    let expiry =
        (mosh_core::conversation::now_ms() + 30 * 86_400_000).div_ceil(86_400_000) * 86_400_000;
    let order = json!({"id":"test-order", "network":"solana-devnet", "product":"mosh-plus-30d",
        "mint":"So11111111111111111111111111111111111111112", "recipient":"11111111111111111111111111111111",
        "amount_atomic":"1000000000", "reference":"So11111111111111111111111111111111111111112",
        "status":"paid", "access_token":"test-only-capability-12345678901234567890", "expires_at_ms":expiry,
        "payment_uri":"solana:11111111111111111111111111111111?amount=1&spl-token=So11111111111111111111111111111111111111112&reference=So11111111111111111111111111111111111111112"});
    assert!(peer
        .ask(json!({"action":"plus_order","argument":order.to_string()}))
        .get("error")
        .is_none());
    let blinded = peer.ask(json!({"action":"plus_prepare"}));
    let metadata = format!("mosh-plus-devnet-v1\0mosh-plus-30d\0{expiry}");
    let derived = key
        .derive_key_pair_for_metadata(metadata.as_bytes())
        .unwrap();
    let signature = derived
        .sk
        .blind_sign(
            STANDARD
                .decode(blinded["blinded"].as_str().unwrap())
                .unwrap(),
        )
        .unwrap();
    assert_eq!(
        peer.ask(json!({"action":"plus_complete","argument":STANDARD.encode(signature.0)}))
            ["active"],
        true
    );
    peer.ask(json!({"action":"plus_visible","visible":true}));
}

fn issuer() -> KeyPair {
    let vector: Value = serde_json::from_str(include_str!(
        "../fixtures/ietf-draft02-public-test-key.json"
    ))
    .unwrap();
    let sk = SecretKey::from_der(
        &STANDARD
            .decode(vector["pkcs8_b64"].as_str().unwrap())
            .unwrap(),
    )
    .unwrap();
    KeyPair {
        pk: sk.public_key().unwrap(),
        sk,
    }
}

#[test]
fn verified_plus_propagates_over_real_dm_group_and_channel_without_chat_messages() {
    let _network = isolated_network_scenario();
    let key = issuer();
    let public_key = STANDARD.encode(key.pk.to_der().unwrap());
    let mut sender = Peer::new_api();
    let mut receiver = Peer::new_api();
    for peer in [&mut sender, &mut receiver] {
        assert!(peer
            .ask(json!({"action":"plus_configure","argument":public_key}))
            .get("error")
            .is_none());
    }
    let invite = sender.ask(json!({"action":"dm_invite"}));
    receiver.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    let session = invite["session_id"].as_str().unwrap();
    wait_connected(&mut receiver, &mut sender, session);
    let group = sender.ask(json!({"action":"plus_group_create"}));
    receiver.ask(json!({"action":"plus_group_join","argument":group["invite_uri"]}));
    let channel = format!("plus-test-{}", rand::random::<u32>());
    for peer in [&mut sender, &mut receiver] {
        peer.ask(json!({"action":"plus_channel","argument":channel}));
    }
    activate(&mut sender, &key);
    wait_badges(
        &mut sender,
        &mut receiver,
        session,
        group["group_id"].as_str().unwrap(),
        &channel,
        true,
    );
    let recipient = receiver.ask(json!({"action":"plus_channel_poll", "argument":channel}));
    let offer = sender.ask(json!({"action":"dm_invite"}));
    assert_eq!(
        sender.ask(json!({"action":"plus_channel_offer", "argument":channel,
        "target":recipient["device_fingerprint"], "invite":offer["invite_uri"]}))["ok"],
        true
    );
    let until = Instant::now() + Duration::from_secs(20);
    loop {
        let snapshot = receiver.ask_until(
            json!({"action":"plus_channel_poll", "argument":channel}),
            until,
        );
        if snapshot["dm_offers"]
            .as_array()
            .unwrap()
            .iter()
            .any(|offer| offer["authenticated"] == true)
        {
            break;
        }
        assert!(
            Instant::now() < until,
            "signed PLUS offer did not arrive: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    sender.ask(json!({"action":"plus_visible","visible":false}));
    wait_badges(
        &mut sender,
        &mut receiver,
        session,
        group["group_id"].as_str().unwrap(),
        &channel,
        false,
    );
    let dm = receiver.ask(json!({"action":"dm_poll","argument":session}));
    assert!(dm["messages"].as_array().unwrap().is_empty());
}

fn wait_badges(
    sender: &mut Peer,
    receiver: &mut Peer,
    dm: &str,
    group: &str,
    channel: &str,
    visible: bool,
) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        for peer in [&mut *sender, &mut *receiver] {
            peer.ask_until(json!({"action":"plus_group_poll","argument":group}), until);
            peer.ask_until(
                json!({"action":"plus_channel_poll","argument":channel}),
                until,
            );
        }
        let snapshot = receiver.ask_until(json!({"action":"plus_snapshot"}), until);
        let identities: Vec<_> = snapshot["peer_badges"]
            .as_array()
            .unwrap()
            .iter()
            .map(|badge| badge["identity"].as_str().unwrap())
            .collect();
        let all_present = identities.contains(&format!("dm:{dm}").as_str())
            && identities
                .iter()
                .any(|id| id.starts_with(&format!("group:{group}:")))
            && identities
                .iter()
                .any(|id| id.starts_with(&format!("channel:{channel}:")));
        if (visible && all_present) || (!visible && identities.is_empty()) {
            return;
        }
        assert!(
            Instant::now() < until,
            "PLUS badge propagation failed: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn a_paid_installation_cannot_adopt_another_account_and_fresh_adoption_rebinds_plus() {
    let _network = isolated_network_scenario();
    let key = issuer();
    let pin = STANDARD.encode(key.pk.to_der().unwrap());
    let mut trusted = Peer::new_api();
    let mut payer = Peer::new_api();
    payer.ask(json!({"action":"plus_configure", "argument":pin}));
    assert_eq!(payer.ask(json!({"action":"snapshot"}))["can_join"], true);
    pair(&mut trusted, &mut payer);
    let adopted = payer.ask(json!({"action":"snapshot"}))["user_id"].clone();
    activate(&mut payer, &key);
    assert_eq!(payer.ask(json!({"action":"snapshot"}))["can_join"], false);
    let mut other = Peer::new_api();
    let qr = other.ask(json!({"action":"qr"}));
    let mut unlinked = Peer::new_api();
    unlinked.ask(
        json!({"action":"plus_configure", "argument":STANDARD.encode(key.pk.to_der().unwrap())}),
    );
    activate(&mut unlinked, &key);
    assert_eq!(
        unlinked.ask(json!({"action":"snapshot"}))["can_join"],
        false
    );
    let rejected =
        unlinked.ask(json!({"action":"import", "argument":qr["qr_uri"], "name":"Payer"}));
    assert_eq!(rejected["error"], "Ineligible");
    assert_eq!(payer.ask(json!({"action":"snapshot"}))["user_id"], adopted);
    assert_eq!(payer.ask(json!({"action":"plus_snapshot"}))["active"], true);
}
