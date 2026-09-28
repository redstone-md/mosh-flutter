use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use serde_json::json;

use super::qr::{PairingQr, QR_LIFETIME_SECONDS};
use super::roster::DeviceRoster;
use super::types::{DeviceDescriptor, DeviceLinkErrorKind};
use super::wire::{self, LinkMessage};

fn device(key: &SigningKey) -> DeviceDescriptor {
    let transport_key = SigningKey::generate(&mut OsRng);
    DeviceDescriptor::new(key, &hex::encode(transport_key.verifying_key().as_bytes()))
}

#[test]
fn only_a_verified_member_can_extend_the_signed_device_roster() {
    let root_key = SigningKey::generate(&mut OsRng);
    let second_key = SigningKey::generate(&mut OsRng);
    let third_key = SigningKey::generate(&mut OsRng);
    let root = device(&root_key);
    let second = device(&second_key);
    let third = device(&third_key);
    let genesis = DeviceRoster::genesis(root.clone(), &root_key).unwrap();
    assert!(genesis.extend(third.clone(), &second_key).is_err());
    let linked = genesis.extend(second.clone(), &root_key).unwrap();
    let delegated = linked.extend(third.clone(), &second_key).unwrap();
    assert_eq!(
        delegated.devices().unwrap(),
        vec![root, second.clone(), third.clone()]
    );
    assert_eq!(delegated.user_id(), genesis.user_id());
    assert!(delegated.extend(second, &root_key).is_err());
    assert!(delegated
        .verifies_addition(
            &genesis,
            &third,
            &hex::encode(second_key.verifying_key().as_bytes())
        )
        .is_err());

    let mut value = serde_json::to_value(&linked).unwrap();
    value["entries"][1]["device"]["name"] = json!("Forged name");
    let forged: DeviceRoster = serde_json::from_value(value).unwrap();
    assert!(forged.devices().is_err());
}

#[test]
fn removal_preserves_other_devices_and_refuses_a_revoked_authority() {
    let root_key = SigningKey::generate(&mut OsRng);
    let removed_key = SigningKey::generate(&mut OsRng);
    let other_key = SigningKey::generate(&mut OsRng);
    let root = device(&root_key);
    let removed = device(&removed_key);
    let other = device(&other_key);
    let roster = DeviceRoster::genesis(root.clone(), &root_key)
        .unwrap()
        .extend(removed.clone(), &root_key)
        .unwrap()
        .extend(other.clone(), &removed_key)
        .unwrap();
    let revoked = roster.revoke(&removed.device_id, &root_key).unwrap();
    assert_eq!(revoked.devices().unwrap(), vec![root.clone(), other]);
    assert_eq!(revoked.user_id(), roster.user_id());
    assert!(revoked.extends(&roster).unwrap());
    assert!(!roster.extends(&revoked).unwrap());
    assert!(revoked
        .extend(device(&SigningKey::generate(&mut OsRng)), &removed_key)
        .is_err());
    assert!(revoked.revoke(&root.device_id, &removed_key).is_err());
    assert!(revoked.revoke(&root.device_id, &root_key).is_err());
    assert!(revoked.revoke(&removed.device_id, &root_key).is_err());
    let mut value = serde_json::to_value(&revoked).unwrap();
    value["entries"][3]["device"] = json!(root);
    let forged: DeviceRoster = serde_json::from_value(value).unwrap();
    assert!(forged.devices().is_err());
}

#[test]
fn signed_pairing_packets_are_encrypted_and_bound_to_the_whole_qr() {
    let joining_key = SigningKey::generate(&mut OsRng);
    let trusted_key = SigningKey::generate(&mut OsRng);
    let qr = PairingQr::new(device(&joining_key), 1000);
    let trusted = device(&trusted_key);
    let roster = DeviceRoster::genesis(trusted.clone(), &trusted_key).unwrap();
    let mut packet = wire::seal(&qr, &trusted_key, LinkMessage::Offer { roster, trusted }).unwrap();
    let (signer, _) = wire::open(&qr, &packet).unwrap();
    assert_eq!(signer, hex::encode(trusted_key.verifying_key().as_bytes()));
    assert!(!packet.windows(signer.len()).any(|w| w == signer.as_bytes()));
    let mut substituted = qr.clone();
    substituted.device.name = "Different desktop".into();
    assert!(wire::open(&substituted, &packet).is_err());
    substituted = qr.clone();
    substituted.expires_at += 1;
    assert!(wire::open(&substituted, &packet).is_err());
    *packet.last_mut().unwrap() ^= 1;
    assert!(wire::open(&qr, &packet).is_err());
    assert!(wire::open(&qr, b"invalid").is_err());
    assert!(wire::open(&qr, &vec![0; wire::MAX_PACKET_BYTES + 1]).is_err());
}

#[test]
fn expired_malformed_and_future_qrs_are_rejected_at_the_protocol_boundary() {
    let key = SigningKey::generate(&mut OsRng);
    let mut qr = PairingQr::new(device(&key), 1000);
    assert!(PairingQr::parse(&qr.uri().unwrap(), 1001).is_ok());
    assert!(
        matches!(PairingQr::parse(&qr.uri().unwrap(), 1000 + QR_LIFETIME_SECONDS),
        Err(error) if error.kind == DeviceLinkErrorKind::Expired)
    );
    qr.expires_at += 1000;
    assert!(PairingQr::parse(&qr.uri().unwrap(), 1000).is_err());
    for uri in ["invalid", "mosh://device-link/%", "mosh://device-link/e30"] {
        assert!(PairingQr::parse(uri, 1000).is_err());
    }
}
