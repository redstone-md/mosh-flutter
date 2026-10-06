import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';

class CallAlreadyInProgress implements Exception {
  const CallAlreadyInProgress();
}

/// Admission for the single application audio owner, including pending starts.
final voiceCallStartProvider =
    NotifierProvider<VoiceCallStartNotifier, bool>(VoiceCallStartNotifier.new);

class VoiceCallStartNotifier extends Notifier<bool> {
  String? _awaitingSnapshot;

  @override
  bool build() {
    ref.listen(conversationListProvider(ConversationKind.dm), (_, next) {
      if (!state && next is AsyncData<ConversationList>) {
        _awaitingSnapshot = null;
      }
    });
    return false;
  }

  Future<Object?> start(String sessionId) async {
    if (state ||
        _awaitingSnapshot != null ||
        ref.read(voiceCallSessionProvider) != null) {
      return const CallAlreadyInProgress();
    }
    state = true;
    try {
      await ref
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
      if (!ref.mounted) return null;
      await ref.read(conversationListProvider(ConversationKind.dm).future);
      if (!ref.mounted) return null;
      if (ref.read(voiceCallSessionProvider) != null) {
        return const CallAlreadyInProgress();
      }
      await ref.read(bridgeFacadeProvider).callStart(sessionId: sessionId);
      if (!ref.mounted) return null;
      _awaitingSnapshot = sessionId;
      try {
        await ref
            .read(conversationListProvider(ConversationKind.dm).notifier)
            .refresh();
        if (ref.mounted &&
            ref.read(conversationListProvider(ConversationKind.dm))
                is AsyncData<ConversationList>) {
          _awaitingSnapshot = null;
        }
      } catch (_) {
        // Retain admission until polling confirms the accepted call's state.
      }
      return null;
    } catch (error) {
      return error;
    } finally {
      if (ref.mounted) state = false;
    }
  }
}
