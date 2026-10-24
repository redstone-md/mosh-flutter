use super::*;

fn descriptor(seed: u8) -> (SigningKey, DeviceDescriptor) {
    let key = SigningKey::from_bytes(&[seed; 32]);
    let device = DeviceDescriptor::new(&key, &hex::encode(key.verifying_key().as_bytes()));
    (key, device)
}

fn fixture() -> (SigningKey, DeviceDescriptor, DeviceRoster, DeviceRoster) {
    let (root, first) = descriptor(11);
    let (_, second) = descriptor(22);
    let genesis = DeviceRoster::genesis(first, &root).unwrap();
    let linked = genesis.extend(second.clone(), &root).unwrap();
    (root, second, genesis, linked)
}

fn legacy_extends(current: &DeviceRoster, base: &DeviceRoster) -> Result<bool> {
    current.devices()?;
    if current.entries.len() < base.entries.len() {
        return Ok(false);
    }
    let prefix = DeviceRoster::from_entries(current.entries[..base.entries.len()].to_vec());
    Ok(prefix.digest()? == base.digest()?)
}

#[test]
fn unchanged_admission_and_revocation_reads_do_not_rehash_verified_rosters() {
    let (_, second, _, linked) = fixture();
    DIGEST_CALLS.set(0);
    for _ in 0..10 {
        assert!(linked.authorizes_admitted(&linked, &second).unwrap());
        assert!(!linked.has_removal_since(&linked).unwrap());
    }
    assert_eq!(
        DIGEST_CALLS.get(),
        0,
        "unchanged permission reads rebuilt digests"
    );
}

#[test]
fn prefixes_forks_and_revocation_results_match_the_legacy_comparison() {
    let (root, second, genesis, linked) = fixture();
    let (_, third) = descriptor(33);
    let fork = genesis.extend(third.clone(), &root).unwrap();
    let removed = linked.revoke(&second.device_id, &root).unwrap();
    let readded = removed.extend(second.clone(), &root).unwrap();
    let rosters = [genesis, linked, fork, removed, readded];
    for current in &rosters {
        for base in &rosters {
            assert_eq!(
                current.extends(base).unwrap(),
                legacy_extends(current, base).unwrap()
            );
        }
    }
    assert!(!rosters[3]
        .authorizes_admitted(&rosters[1], &second)
        .unwrap());
    assert!(!rosters[4]
        .authorizes_admitted(&rosters[1], &second)
        .unwrap());
    assert!(rosters[4]
        .authorizes_admitted(&rosters[4], &second)
        .unwrap());
}

#[test]
fn malformed_current_chain_is_rejected_before_prefix_comparison() {
    let (_, _, genesis, linked) = fixture();
    let encoded = serde_json::to_value(&linked).unwrap();
    let mut changed = encoded.clone();
    changed["entries"][1]["device"]["name"] = serde_json::json!("forged");
    let forged: DeviceRoster = serde_json::from_value(changed).unwrap();
    assert_eq!(forged.extends(&linked).unwrap_err().kind, invalid().kind);
    assert_eq!(
        forged.extends(&linked).unwrap_err().kind,
        legacy_extends(&forged, &linked).unwrap_err().kind
    );
    let empty = DeviceRoster::from_entries(Vec::new());
    assert_eq!(empty.extends(&genesis).unwrap_err().kind, invalid().kind);
    let restored: DeviceRoster = serde_json::from_value(encoded.clone()).unwrap();
    assert!(restored.extends(&linked).unwrap());
    assert_eq!(serde_json::to_value(&restored).unwrap(), encoded);
}
