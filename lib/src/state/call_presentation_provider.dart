import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart'
    show CallForm;
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';

/// Where the main window draws its call, or null without one. The call host
/// and the title bar both read it: the host is under the router, the title
/// bar above it.
///
/// A call opens over the window, except one ringing on the desktop, which
/// must not take the window from what the user is doing. Minimized it is a
/// tile once it has had video, else the desktop's card while it rings and
/// its title bar plate after, and the phone's strip.
final callPresentationProvider =
    NotifierProvider<CallPresentationNotifier, CallForm?>(
        CallPresentationNotifier.new);

class CallPresentationNotifier extends Notifier<CallForm?> {
  String? _call;
  bool _open = true;
  bool _video = false;

  @override
  CallForm? build() {
    // Without the engine the call is a strip under the app, never open.
    if (ref.watch(nativeCallOwnerProvider) == null) return null;
    final session =
        ref.watch(voiceCallSessionProvider.select((s) => s?.sessionId));
    if (session == null) {
      _call = null;
      return null;
    }
    final desktop = ref.watch(desktopWindowControllerProvider) != null;
    final (call, ringing, video) =
        ref.watch(voiceCallOrchestratorProvider(session).select((s) => (
              s.dialog.callId,
              _ringing(s.dialog),
              s.nativeMedia != null &&
                  (s.cameraRequested || s.nativeMedia!.remoteCamera)
            )));
    if (_call != call) {
      _call = call;
      _open = !(desktop && ringing);
      _video = false;
    }
    // A call that has shown video keeps its tile when the cameras go off.
    _video |= video;
    if (_open) return CallForm.open;
    if (_video) return CallForm.tile;
    if (!desktop) return CallForm.strip;
    return ringing ? CallForm.card : CallForm.plate;
  }

  static bool _ringing(CallDialog dialog) =>
      dialog is IncomingCallDialog && !dialog.pending.answerPending;

  /// Opens the call over the window.
  void open() => _set(true);

  /// Leaves the call running beside the chats.
  void minimize() => _set(false);

  void _set(bool open) {
    if (state == null || _open == open) return;
    _open = open;
    ref.invalidateSelf();
  }
}
