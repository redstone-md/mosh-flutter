use super::*;

fn group_with_dictionary<Provider: OpenMlsProvider + Default>(
    ciphersuite: Ciphersuite,
    dictionary: Option<AppDataDictionary>,
) -> (
    Provider,
    openmls_basic_credential::SignatureKeyPair,
    MlsGroup,
) {
    let provider = Provider::default();
    let (credential, signer) = crate::prelude::test_utils::new_credential(
        &provider,
        b"Alice",
        ciphersuite.signature_algorithm(),
    );
    let mut extensions = vec![Extension::RequiredCapabilities(
        RequiredCapabilitiesExtension::new(
            &[ExtensionType::AppDataDictionary],
            &[ProposalType::AppDataUpdate],
            &[],
        ),
    )];
    if let Some(dictionary) = dictionary {
        extensions.push(Extension::AppDataDictionary(
            AppDataDictionaryExtension::new(dictionary),
        ));
    }
    let config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .capabilities(Capabilities::new(
            None,
            None,
            Some(&[ExtensionType::AppDataDictionary]),
            Some(&[ProposalType::AppDataUpdate]),
            None,
        ))
        .with_group_context_extensions(Extensions::from_vec(extensions).unwrap())
        .build();
    let group = MlsGroup::new(&provider, &signer, &config, credential).unwrap();
    (provider, signer, group)
}

#[openmls_test]
fn review_remove_requires_existing_component() {
    let mut populated = AppDataDictionary::new();
    populated.insert(99, b"existing".to_vec());
    for with_gce in [false, true] {
        for dictionary in [
            None,
            Some(AppDataDictionary::new()),
            Some(populated.clone()),
        ] {
            let expected_success = dictionary.as_ref().is_some_and(|d| d.contains(&99));
            let (provider, signer, mut group) =
                group_with_dictionary::<Provider>(ciphersuite, dictionary);
            if with_gce {
                group
                    .propose_group_context_extensions(
                        &provider,
                        group.extensions().clone(),
                        &signer,
                    )
                    .unwrap();
            }
            let mut stage = group
                .commit_builder()
                .consume_proposal_store(true)
                .add_proposals(vec![Proposal::AppDataUpdate(Box::new(
                    AppDataUpdateProposal::remove(99),
                ))])
                .load_psks(provider.storage())
                .unwrap();
            let mut updater = stage.app_data_dictionary_updater();
            updater.remove(&99);
            stage.with_app_data_dictionary_updates(updater.changes());
            let result = stage.build(provider.rand(), provider.crypto(), &signer, |_| true);
            if expected_success {
                assert!(result.is_ok());
            } else {
                assert!(matches!(
                    result,
                    Err(CreateCommitError::AppDataUpdateValidationError(
                        AppDataUpdateValidationError::CannotRemoveNonexistentComponent
                    ))
                ));
            }
        }
    }
}
