part of 'scriptable_bridge.dart';

mixin _BridgeInvitations on _ScriptableBridgeState {
  @override
  Future<InviteCreated> createPendingInvite({
    required StartSessionRequest request,
  }) =>
      runScripted(BridgeMethod.createPendingInvite, {'request': request}, () {
        final invite = _createInvite(request);
        conversations.hiddenSessions.add(invite.sessionId);
        conversations.pendingInvites[invite.sessionId] = invite;
        return invite;
      });

  @override
  Future<List<InviteCreated>> listPendingInvites() => runScripted(
        BridgeMethod.listPendingInvites,
        const {},
        () => conversations.pendingInvites.values.toList(),
      );

  @override
  Future<InviteCreated> replaceInvite({required String sessionId}) =>
      runScripted(
        BridgeMethod.replaceInvite,
        {'sessionId': sessionId},
        () {
          final session = conversations.sessions[sessionId];
          if (session == null ||
              !session.inviteAvailable ||
              session.inviteUri == null) {
            throw StateError('Invitation is no longer available');
          }
          final old = Uri.parse(session.inviteUri!);
          final uri = old.replace(queryParameters: {
            ...old.queryParameters,
            'revision': '${++_inviteRevision}',
          }).toString();
          final invite = InviteCreated(
            inviteUri: uri,
            sessionId: sessionId,
            meshId: session.meshId,
            fingerprint: session.fingerprint,
            listenAddress: '127.0.0.1:8765',
          );
          conversations.sessions[sessionId] =
              copySessionSnapshot(session, inviteUri: uri);
          if (conversations.hiddenSessions.contains(sessionId)) {
            conversations.pendingInvites[sessionId] = invite;
          }
          return invite;
        },
      );

  @override
  Future<SessionSnapshot> openSession({required String sessionId}) =>
      runScripted(
        BridgeMethod.openSession,
        {'sessionId': sessionId},
        () {
          final session = conversations.sessions[sessionId];
          if (session == null) throw StateError('Unknown conversation');
          conversations.hiddenSessions.remove(sessionId);
          conversations.pendingInvites.remove(sessionId);
          return session;
        },
      );
}
