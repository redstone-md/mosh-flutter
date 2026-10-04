part of 'scriptable_bridge.dart';

mixin _BridgeOrganizations on _ScriptableBridgeState {
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) => runScripted(
        BridgeMethod.joinOrg,
        {'request': request},
        () {
          final org = cannedOrgSnapshot(
            orgPubkey: orgPubkeyFromBundleUri(request.bundleUri),
          );
          _orgs[org.orgPubkey] = org;
          return org;
        },
      );

  @override
  Future<void> leaveOrg({required String orgPubkey}) =>
      runScripted(BridgeMethod.leaveOrg, {'orgPubkey': orgPubkey}, () {
        _orgs.remove(orgPubkey);
      });

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
      runScripted(BridgeMethod.sendOrgDmOffer, {
        'orgPubkey': orgPubkey,
        'targetPeerId': targetPeerId,
        'displayName': displayName,
        'listenPort': listenPort,
        'staticPeer': staticPeer,
      }, () {
        final id = 'fake-org-dm-${conversations.sessions.length + 1}';
        final invite = InviteCreated(
          inviteUri: 'mosh://invite?session=$id&fp=00#fp=00',
          sessionId: id,
          meshId: '',
          fingerprint: '00',
          listenAddress: '',
        );
        conversations.sessions[id] = fakeSession(
          sessionId: id,
          displayName: displayName,
          role: 'inviter',
          inviteUri: invite.inviteUri,
          fingerprint: invite.fingerprint,
        );
        return invite;
      });

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
      runScripted(BridgeMethod.acceptOrgGroupOffer, {
        'orgPubkey': orgPubkey,
        'offerId': offerId,
        'displayName': displayName,
        'listenPort': listenPort,
        'staticPeer': staticPeer,
      }, () {
        final group = cannedGroupSnapshot(
          groupId: 'fake-org-group-accept',
          displayName: displayName,
          deviceFingerprint: '00',
          creatorFingerprint: '00',
          memberCount: BigInt.one,
          inviteUri: 'mosh://group?session=fake-org-group-accept&fp=00#fp=00',
          orgPubkey: orgPubkey,
        );
        conversations.groups[group.groupId] = group;
        return group;
      });

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
