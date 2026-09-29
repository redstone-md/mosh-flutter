use super::*;
use openmls::test_utils::test_framework::errors::SetupError;

#[openmls_test]
fn unknown_leaf_returns_none() {
    let setup = MlsGroupTestSetup::<Provider>::new(
        MlsGroupCreateConfig::test_default(ciphersuite),
        1,
        CodecUse::SerializedMessages,
    );
    let group_id = setup.create_group(ciphersuite).unwrap();
    let groups = setup.groups.read().unwrap();
    let group = groups.get(&group_id).unwrap();
    assert_eq!(
        setup.identity_by_index(0, group),
        Some(group.members[0].1.clone())
    );
    assert_eq!(setup.identity_by_index(99, group), None);
}

#[openmls_test]
fn empty_setup_cannot_create_group() {
    let setup = MlsGroupTestSetup::<Provider>::new(
        MlsGroupCreateConfig::test_default(ciphersuite),
        0,
        CodecUse::SerializedMessages,
    );
    assert!(matches!(
        setup.create_group(ciphersuite),
        Err(SetupError::NotEnoughClients)
    ));
    assert!(setup.groups.read().unwrap().is_empty());
}

#[openmls_test]
fn zero_size_group_has_no_side_effects() {
    let setup = MlsGroupTestSetup::<Provider>::new(
        MlsGroupCreateConfig::test_default(ciphersuite),
        1,
        CodecUse::SerializedMessages,
    );
    assert!(matches!(
        setup.create_random_group(0, ciphersuite, noop_authentication_service),
        Err(SetupError::Unknown)
    ));
    assert!(setup.groups.read().unwrap().is_empty());
}
