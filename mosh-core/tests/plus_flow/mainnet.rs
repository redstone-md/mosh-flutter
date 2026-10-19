use super::*;
use sha2::{Digest, Sha256};

#[test]
fn production_status_and_visibility_sync_to_linked_and_later_devices_over_real_moss() {
    let _network = isolated_network_scenario();
    let key = issuer();
    let pin = STANDARD.encode(key.pk.to_der().unwrap());
    let mut founder = Peer::new_api();
    let mut sibling = Peer::new_api();
    pair(&mut founder, &mut sibling);
    configure(&mut founder, &pin);
    configure(&mut sibling, &pin);
    assert!(sibling
        .ask(json!({"action":"plus_series_prepare"}))
        .get("error")
        .is_some());
    let series = founder.ask(json!({"action":"plus_series_prepare"}));
    assert!(
        series.get("error").is_none(),
        "series initialization failed: {series}"
    );
    founder.ask(json!({"action":"plus_series_registered","argument":series["id"]}));
    wait(&mut founder, true, false, false);
    wait(&mut sibling, true, false, false);
    activate(&mut founder, &key, &pin, series["id"].as_str().unwrap());
    wait(&mut sibling, true, true, true);
    founder.stop();
    sibling.ask(json!({"action":"plus_visible","visible":false}));
    let mut newcomer = Peer::new_api();
    pair(&mut sibling, &mut newcomer);
    configure(&mut newcomer, &pin);
    wait(&mut newcomer, true, true, false);
    sibling.restart();
    configure(&mut sibling, &pin);
    wait(&mut sibling, true, true, false);
}

fn configure(peer: &mut Peer, pin: &str) {
    let snapshot = peer.ask(json!({"action":"plus_mainnet_configure","argument":pin}));
    assert!(
        snapshot.get("error").is_none(),
        "production issuer failed: {snapshot}"
    );
}

fn wait(peer: &mut Peer, ready: bool, active: bool, visible: bool) {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let snapshot = peer.ask_until(json!({"action":"plus_snapshot"}), deadline);
        if snapshot["checkout_ready"] == ready
            && snapshot["active"] == active
            && snapshot["visible"] == visible
        {
            return;
        }
        assert!(
            Instant::now() < deadline,
            "PLUS account metadata did not converge"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn activate(peer: &mut Peer, key: &KeyPair, pin: &str, series: &str) {
    let now = mosh_core::conversation::now_ms();
    let start = now / 86_400_000 * 86_400_000;
    let end = (now + 30 * 86_400_000).div_ceil(86_400_000) * 86_400_000;
    let key_id = hex::encode(Sha256::digest(pin.as_bytes()));
    let order = json!({ "id":"first", "network":"solana-mainnet", "product":"mosh-plus-supporter-30d",
        "asset":"USDC", "token_decimals":6, "issuer_key_id":key_id, "series_id":series,
        "mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "recipient":"11111111111111111111111111111111",
        "amount_atomic":"5000000", "reference":"So11111111111111111111111111111111111111112", "status":"paid",
        "access_token":"test-only-purchase-capability-123456789", "valid_from_ms":start, "expires_at_ms":end,
        "payment_uri":"solana:11111111111111111111111111111111?amount=5&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&reference=So11111111111111111111111111111111111111112" });
    let saved = peer.ask(json!({"action":"plus_order","argument":order.to_string()}));
    assert!(
        saved.get("error").is_none(),
        "production order rejected: {saved}"
    );
    let blind = peer.ask(json!({"action":"plus_order_prepare","argument":"first"}));
    let metadata =
        format!("mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{key_id}\0{start}\0{end}");
    let derived = key
        .derive_key_pair_for_metadata(metadata.as_bytes())
        .unwrap();
    let signature = derived
        .sk
        .blind_sign(STANDARD.decode(blind["blinded"].as_str().unwrap()).unwrap())
        .unwrap();
    assert_eq!(peer.ask(json!({"action":"plus_order_complete","id":"first","argument":STANDARD.encode(signature.0)}))["active"], true);
    peer.ask(json!({"action":"plus_visible","visible":true}));
}
