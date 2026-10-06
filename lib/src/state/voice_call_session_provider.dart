import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';

/// Retains the originating DM while its call exists. Navigation never selects
/// an audio owner. Other pending calls cannot open a second microphone.
final voiceCallSessionProvider =
    NotifierProvider<VoiceCallSessionNotifier, SessionSnapshot?>(
        VoiceCallSessionNotifier.new);

class VoiceCallSessionNotifier extends Notifier<SessionSnapshot?> {
  String? _selectedId;

  @override
  SessionSnapshot? build() {
    ref.listen(conversationListProvider(ConversationKind.dm), (_, next) {
      if (next is AsyncData<ConversationList>) state = _pick(next.value);
    });
    return _pick(ref.read(conversationListProvider(ConversationKind.dm)).value);
  }

  SessionSnapshot? _pick(ConversationList? list) {
    final calls = sessionsOf(list).where((session) =>
        session.activeCall != null ||
        session.pendingCall != null ||
        session.outgoingCall != null);
    for (final session in calls) {
      if (session.sessionId == _selectedId) return session;
    }
    final selected =
        calls.where((session) => session.activeCall != null).firstOrNull ??
            calls.firstOrNull;
    _selectedId = selected?.sessionId;
    return selected;
  }
}
