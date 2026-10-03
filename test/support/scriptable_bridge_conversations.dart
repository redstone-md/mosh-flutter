part of 'scriptable_bridge.dart';

mixin _BridgeConversations on _ScriptableBridgeState {
  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      runScripted(BridgeMethod.createInvite, {'request': request}, () {
        final seeded = _invite;
        final sessionId =
            seeded?.sessionId ?? 'fake-${conversations.sessions.length + 1}';
        final fingerprint = seeded?.fingerprint ?? fakeFingerprint(sessionId);
        final inviteUri = seeded?.inviteUri ??
            'mosh://invite?mesh=fakemesh&session=$sessionId#fp=$fingerprint';
        conversations.sessions[sessionId] = fakeSession(
          sessionId: sessionId,
          displayName: request.displayName,
          role: 'inviter',
          inviteUri: inviteUri,
          fingerprint: fingerprint,
        );
        return seeded ??
            InviteCreated(
              inviteUri: inviteUri,
              sessionId: sessionId,
              meshId: 'fakemesh',
              fingerprint: fingerprint,
              listenAddress: '127.0.0.1:${request.listenPort}',
            );
      });

  @override
  Future<SessionSnapshot> acceptInvite(
          {required AcceptInviteRequest request}) =>
      runScripted(BridgeMethod.acceptInvite, {'request': request}, () {
        final sessionId = 'fake-accept-${conversations.sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: request.displayName,
          role: 'invitee',
          inviteUri: request.inviteUri,
          fingerprint: fakeFingerprint(sessionId),
        );
        conversations.sessions[sessionId] = snapshot;
        return snapshot;
      });

  @override
  Future<SessionListSnapshot> listSessions() => runScripted(
        BridgeMethod.listSessions,
        const {},
        () => SessionListSnapshot(
            sessions: conversations.sessions.values.toList()),
      );

  @override
  Future<ChannelListSnapshot> listChannels() => runScripted(
        BridgeMethod.listChannels,
        const {},
        () => ChannelListSnapshot(
            channels: conversations.channels.values.toList()),
      );

  @override
  Future<GroupListSnapshot> listGroups() => runScripted(
        BridgeMethod.listGroups,
        const {},
        () => GroupListSnapshot(groups: conversations.groups.values.toList()),
      );

  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      runScripted(
          BridgeMethod.joinChannel,
          {'request': request},
          () =>
              conversations.channels[request.name] ??
              cannedChannelSnapshot(
                  name: request.name, displayName: request.displayName));

  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      runScripted(BridgeMethod.createGroup, {'request': request}, () {
        final label = request.label ?? '';
        final groupId = 'fake-group-${label.isEmpty ? 'untitled' : label}';
        return GroupCreated(
          groupId: groupId,
          meshId: '',
          inviteUri: 'mosh://group/$groupId',
          fingerprint: '',
          label: request.label,
        );
      });

  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      runScripted(BridgeMethod.joinGroup, {'request': request}, () {
        final groupId = groupIdFromInviteUri(request.inviteUri);
        return conversations.groups[groupId] ??
            cannedGroupSnapshot(
              groupId: groupId,
              displayName: request.displayName,
              memberCount: BigInt.one,
              inviteUri: request.inviteUri,
              orgPubkey: request.orgPubkey,
            );
      });

  // The outbound DM-offer sends no-op: there is no real peer to deliver to,
  // matching the dismiss pair on the seam. Both must complete normally so
  // the popover UI resolves.
  @override
  Future<void> sendChannelDmOffer({
    required String channelName,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      runScripted(
          BridgeMethod.sendChannelDmOffer,
          {
            'channelName': channelName,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});

  @override
  Future<void> sendGroupDmOffer({
    required String groupId,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      runScripted(
          BridgeMethod.sendGroupDmOffer,
          {
            'groupId': groupId,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});
}
