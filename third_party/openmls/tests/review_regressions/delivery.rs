use openmls::{prelude::*, test_utils::single_group_test_framework::*};
use openmls_test::openmls_test;

fn group<'a, P: OpenMlsProvider>(
    alice: &'a CorePartyState<P>,
    bob: &'a CorePartyState<P>,
    ciphersuite: Ciphersuite,
) -> GroupState<'a, P> {
    let config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .use_ratchet_tree_extension(true)
        .build();
    let mut group = GroupState::new_from_party(
        GroupId::from_slice(b"delivery regression"),
        alice.generate_pre_group(ciphersuite),
        config.clone(),
    )
    .unwrap();
    group
        .add_member(AddMemberConfig {
            adder: "alice",
            addees: vec![bob.generate_pre_group(ciphersuite)],
            join_config: config.join_config().clone(),
            tree: None,
        })
        .unwrap();
    group
}

#[openmls_test]
fn delivery_accepts_application_messages() {
    let alice_party = CorePartyState::<Provider>::new("alice");
    let bob_party = CorePartyState::<Provider>::new("bob");
    let mut group = group(&alice_party, &bob_party, ciphersuite);
    let [alice, bob] = group.members_mut(&["alice", "bob"]);
    let message = alice
        .group
        .create_message(&alice_party.provider, &alice.party.signer, b"hello")
        .unwrap();
    let epoch = bob.group.epoch();
    bob.deliver_and_apply(message.into()).unwrap();
    assert_eq!(bob.group.epoch(), epoch);
    assert_eq!(bob.group.pending_proposals().count(), 0);
}

#[openmls_test]
fn delivery_queues_member_proposals_for_a_commit() {
    let alice_party = CorePartyState::<Provider>::new("alice");
    let bob_party = CorePartyState::<Provider>::new("bob");
    let mut group = group(&alice_party, &bob_party, ciphersuite);
    let [alice, bob] = group.members_mut(&["alice", "bob"]);
    let (proposal, _) = alice
        .group
        .propose_self_update(
            &alice_party.provider,
            &alice.party.signer,
            LeafNodeParameters::default(),
        )
        .unwrap();
    bob.deliver_and_apply(proposal.into()).unwrap();
    assert_eq!(bob.group.pending_proposals().count(), 1);
    let (commit, _, _) = bob
        .group
        .commit_to_pending_proposals(&bob_party.provider, &bob.party.signer)
        .unwrap();
    alice.deliver_and_apply(commit.into()).unwrap();
    bob.group.merge_pending_commit(&bob_party.provider).unwrap();
    assert_eq!(
        alice.group.export_ratchet_tree(),
        bob.group.export_ratchet_tree()
    );
}

#[openmls_test]
fn delivery_queues_external_join_proposals() {
    let alice_party = CorePartyState::<Provider>::new("alice");
    let bob_party = CorePartyState::<Provider>::new("bob");
    let charlie_party = CorePartyState::<Provider>::new("charlie");
    let mut group = group(&alice_party, &bob_party, ciphersuite);
    let [alice] = group.members_mut(&["alice"]);
    let charlie = charlie_party.generate_pre_group(ciphersuite);
    let proposal = JoinProposal::new::<<Provider as OpenMlsProvider>::StorageProvider>(
        charlie.key_package_bundle.key_package().clone(),
        alice.group.group_id().clone(),
        alice.group.epoch(),
        &charlie.signer,
    )
    .unwrap();
    alice.deliver_and_apply(proposal.into()).unwrap();
    assert_eq!(alice.group.pending_proposals().count(), 1);
    let staged = alice
        .group
        .commit_builder()
        .consume_proposal_store(true)
        .load_psks(alice_party.provider.storage())
        .unwrap()
        .build(
            alice_party.provider.rand(),
            alice_party.provider.crypto(),
            &alice.party.signer,
            |_| true,
        )
        .unwrap()
        .stage_commit(&alice_party.provider)
        .unwrap();
    assert!(staged.welcome().is_some());
    alice
        .group
        .merge_pending_commit(&alice_party.provider)
        .unwrap();
    assert_eq!(alice.group.members().count(), 3);
}
