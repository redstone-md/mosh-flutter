use mosh_core::{mls_crypto::MlsSessionCrypto, persistence::Persistence};
use serde_json::{json, Value};

pub fn command(store: &Persistence, action: &str, id: &str, command: &Value) -> Value {
    let record = store
        .list_sessions()
        .unwrap()
        .into_iter()
        .map(|bytes| serde_json::from_slice::<Value>(&bytes).unwrap())
        .find(|record| record["session_id"] == id)
        .unwrap();
    let signer: Vec<u8> = serde_json::from_value(record["signer_public"].clone()).unwrap();
    let group: Vec<u8> = serde_json::from_value(record["group_id"].clone()).unwrap();
    let snapshot = store.get_mls_snapshot(id).unwrap().unwrap();
    let mut crypto = MlsSessionCrypto::restore(
        record["display_name"].as_str().unwrap(),
        &signer,
        &snapshot,
        &group,
    )
    .unwrap();
    match action {
        "crypto_status" => json!({"epoch":crypto.epoch(), "members":crypto.member_count()}),
        "crypto_encrypt" => json!({
            "ciphertext": hex::encode(crypto.encrypt(command["body"].as_str().unwrap().as_bytes()).unwrap()),
            "epoch": crypto.epoch(),
            "members": crypto.member_count(),
        }),
        "crypto_decrypt" => {
            match crypto.decrypt(&hex::decode(command["ciphertext"].as_str().unwrap()).unwrap()) {
                Ok(body) => json!({"plaintext":String::from_utf8(body).unwrap()}),
                Err(error) => json!({"error":error.to_string()}),
            }
        }
        _ => panic!("unknown crypto command"),
    }
}
