part of 'scriptable_bridge.dart';

mixin _BridgeOrganizations on _ScriptableBridgeState {
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) => runScripted(
        BridgeMethod.joinOrg,
        {'request': request},
        () => cannedOrgSnapshot(
          orgPubkey: orgPubkeyFromBundleUri(request.bundleUri),
        ),
      );

  @override
  Future<void> leaveOrg({required String orgPubkey}) =>
      runScripted(BridgeMethod.leaveOrg, {'orgPubkey': orgPubkey}, () {});

  @override
  Future<List<OrgSnapshot>> listOrgs() =>
      runScripted(BridgeMethod.listOrgs, const {}, () => _orgs.values.toList());

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) => runScripted(
      BridgeMethod.pollOrg,
      {'orgPubkey': orgPubkey},
      () => _orgs[orgPubkey] ?? cannedOrgSnapshot(orgPubkey: orgPubkey));

  @override
  Future<InviteCreated> sendOrgDmOffer({
    required String orgPubkey,
    required String targetPeerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(
          BridgeMethod.sendOrgDmOffer,
          {
            'orgPubkey': orgPubkey,
            'targetPeerId': targetPeerId,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => InviteCreated(
                inviteUri: 'mosh://invite?session=fake-org-dm&fp=00#fp=00',
                sessionId: 'fake-org-dm-${conversations.sessions.length + 1}',
                meshId: '',
                fingerprint: '00',
                listenAddress: '',
              ));

  @override
  Future<SessionSnapshot> acceptOrgDmOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(BridgeMethod.acceptOrgDmOffer, {
        'orgPubkey': orgPubkey,
        'offerId': offerId,
        'displayName': displayName,
        'listenPort': listenPort,
        'staticPeer': staticPeer,
      }, () {
        final sessionId =
            'fake-org-accept-${conversations.sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: displayName,
          role: 'invitee',
          inviteUri: 'mosh://invite?session=$sessionId&fp=00#fp=00',
          fingerprint: '00',
        );
        conversations.sessions[sessionId] = snapshot;
        return snapshot;
      });

  @override
  Future<void> dismissOrgDmOffer({
    required String orgPubkey,
    required String offerId,
  }) =>
      runScripted(BridgeMethod.dismissOrgDmOffer,
          {'orgPubkey': orgPubkey, 'offerId': offerId}, () {});

  @override
  Future<GroupCreated> createOrgGroup({
    required String orgPubkey,
    String? label,
    required List<String> memberPeerIds,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(
          BridgeMethod.createOrgGroup,
          {
            'orgPubkey': orgPubkey,
            'label': label,
            'memberPeerIds': memberPeerIds,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => GroupCreated(
                groupId: 'fake-org-group-${conversations.groups.length + 1}',
                meshId: '',
                inviteUri: 'mosh://group?session=fake-org-group&fp=00#fp=00',
                fingerprint: '00',
                label: label,
              ));

  @override
  Future<GroupSnapshot> acceptOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(
          BridgeMethod.acceptOrgGroupOffer,
          {
            'orgPubkey': orgPubkey,
            'offerId': offerId,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => cannedGroupSnapshot(
                groupId: 'fake-org-group-accept',
                displayName: displayName,
                deviceFingerprint: '00',
                creatorFingerprint: '00',
                memberCount: BigInt.one,
                inviteUri:
                    'mosh://group?session=fake-org-group-accept&fp=00#fp=00',
                orgPubkey: orgPubkey,
              ));

  @override
  Future<void> dismissOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
  }) =>
      runScripted(BridgeMethod.dismissOrgGroupOffer,
          {'orgPubkey': orgPubkey, 'offerId': offerId}, () {});

  @override
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  }) =>
      runScripted(
          BridgeMethod.orgGroupInviteMembers,
          {
            'orgPubkey': orgPubkey,
            'groupId': groupId,
            'memberPeerIds': memberPeerIds,
          },
          () {});
}
