import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_decline.dart';
import 'package:mosh/src/features/voice_call/system_call_mirror.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';

/// Keeps the system call screen in step with the app's call for the life of
/// the process. It holds the call's orchestrator, so a call answered on a
/// locked iPhone, with no widget built, still gets its media.
final systemCallMirrorProvider = Provider<SystemCallMirror?>((ref) {
  final screen = ref.watch(iosSystemCallsProvider);
  if (screen == null) return null;
  String? sessionId;
  ProviderSubscription<VoiceCallOrchestratorState>? call;
  VoiceCallOrchestratorNotifier? orchestrator() => sessionId == null
      ? null
      : ref.read(voiceCallOrchestratorProvider(sessionId!).notifier);

  final mirror = SystemCallMirror(screen,
      answer: (id) async => orchestrator()?.acceptCall(id),
      end: (id) async => orchestrator()?.endCall(id, kCallDeclineReasonHangup),
      mute: (callId, muted) {
        final session = sessionId;
        if (session == null) return;
        if (ref.read(voiceCallOrchestratorProvider(session)).muted != muted) {
          orchestrator()?.toggleMute();
        }
      });

  void follow(SessionSnapshot? session) {
    if (session?.sessionId == sessionId) return;
    call?.close();
    call = null;
    sessionId = session?.sessionId;
    final id = sessionId;
    if (id == null) {
      mirror.show(const NoCallDialog());
      return;
    }
    call = ref.listen(voiceCallOrchestratorProvider(id),
        (_, next) => mirror.show(next.dialog),
        fireImmediately: true);
  }

  ref.listen(voiceCallSessionProvider, (_, next) => follow(next),
      fireImmediately: true);
  screen.onAction = mirror.act;
  ref.onDispose(() {
    call?.close();
    screen.onAction = null;
  });
  return mirror;
});
