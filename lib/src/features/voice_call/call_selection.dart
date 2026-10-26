import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Retain the current call across unrelated notifications and navigation.
SessionSnapshot? selectCallSession(Iterable<SessionSnapshot> sessions,
    {String? selectedId}) {
  final calls = sessions.where((session) =>
      session.activeCall != null ||
      session.pendingCall != null ||
      session.outgoingCall != null);
  for (final session in calls) {
    if (session.sessionId == selectedId) return session;
  }
  return calls.where((session) => session.activeCall != null).firstOrNull ??
      calls.firstOrNull;
}
