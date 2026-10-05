use super::identity::DeviceIdentity;

/// Install a verified own-device roster while leaving post-link certificates pending.
pub(crate) fn link_accounts(mut root: DeviceIdentity, mut linked: DeviceIdentity) -> String {
    let roster = root
        .roster()
        .extend(linked.device().clone(), &root.key())
        .unwrap();
    let user = roster.user_id();
    root.record.roster = roster.clone();
    linked.record.roster = roster;
    for identity in [root, linked] {
        identity
            .persistence()
            .put_device_link(&serde_json::to_vec(&identity.record).unwrap())
            .unwrap();
    }
    user
}

pub(crate) fn certify_device(root: DeviceIdentity, mut linked: DeviceIdentity) {
    linked.record.account_certificate = Some(
        root.account_certificate()
            .unwrap()
            .unwrap()
            .issue(&linked.device().signing_public_key, &root.key())
            .unwrap(),
    );
    linked
        .persistence()
        .put_device_link(&serde_json::to_vec(&linked.record).unwrap())
        .unwrap();
}
