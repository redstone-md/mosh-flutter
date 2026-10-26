import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/voice_call/call_selection.dart';
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
    final waiting = ref.read(androidWaitingOwnerProvider);
    if (waiting != null) {
      void changed() {
        state = waiting.calls.snapshot;
        _selectedId = state?.sessionId;
      }

      waiting.calls.addListener(changed);
      ref.onDispose(() => waiting.calls.removeListener(changed));
      return waiting.calls.snapshot;
    }
    ref.listen(conversationListProvider(ConversationKind.dm), (_, next) {
      if (next is AsyncData<ConversationList>) state = _pick(next.value);
    });
    return _pick(ref.read(conversationListProvider(ConversationKind.dm)).value);
  }

  SessionSnapshot? _pick(ConversationList? list) {
    final selected =
        selectCallSession(sessionsOf(list), selectedId: _selectedId);
    _selectedId = selected?.sessionId;
    return selected;
  }
}
