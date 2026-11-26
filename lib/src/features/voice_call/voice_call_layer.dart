import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'call_view_wiring.dart';
import 'call_notification_details.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'call_video_textures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart' show windowManager;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_parts.dart'
    show CallFullScreen;
import 'package:mosh/src/state/voice_call_start_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

/// Inline controls for the originating DM, independent of the visible route.
/// The notifier owns the ringtone, timeout and audio; this widget owns no route.
class VoiceCallLayer extends ConsumerStatefulWidget {
  const VoiceCallLayer({
    super.key,
    required this.sessionId,
    required this.l,
    this.onVoiceCallError,
    this.onOpenConversation,
    this.onOpen,
    this.form = CallForm.strip,
    this.video,
    this.onMinimize,
    this.peerOverride,
    this.fullScreen,
  });

  final String sessionId;
  final String? peerOverride;
  final AppLocalizations l;
  final void Function(String? message)? onVoiceCallError;
  final VoidCallback? onOpenConversation;
  final VoidCallback? onOpen;

  /// Where the call is drawn. The title bar draws the plate itself, so in
  /// that form the layer keeps the call's notification and errors and shows
  /// nothing.
  final CallForm form;
  final ValueListenable<CallVideoPictures>? video;
  final VoidCallback? onMinimize;
  final CallFullScreen? fullScreen;

  @override
  ConsumerState<VoiceCallLayer> createState() => _VoiceCallLayerState();
}

class _VoiceCallLayerState extends ConsumerState<VoiceCallLayer> {
  String? _notifiedCall;
  int _notificationGeneration = 0;
  Timer? _notificationRetry;
  int? _notificationId;
  FlutterLocalNotificationsPlugin? _notificationPlugin;
  Future<void> _notificationWork = Future.value();

  @override
  void dispose() {
    _clearNotification();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceCallOrchestratorProvider(widget.sessionId));
    ref.listen(
        voiceCallOrchestratorProvider(widget.sessionId).select((s) => s.error),
        (_, error) => _reportError(error));
    final dialog = state.dialog;
    if (dialog is IncomingCallDialog &&
        !dialog.pending.answerPending &&
        !state.busy) {
      if (_notifiedCall != dialog.callId) {
        _clearNotification();
        _notifiedCall = dialog.callId;
        unawaited(_notify(dialog));
      }
    } else {
      _notifiedCall = null;
      _clearNotification();
    }
    final call = callViewOf(widget.sessionId, state, widget.l,
        peerOverride: widget.peerOverride);
    if (call == null || widget.form == CallForm.plate) {
      return const SizedBox.shrink();
    }
    return CallView(
        call: call,
        form: widget.form,
        video: widget.video,
        onDeviceSelected: _act,
        onOpen: widget.onOpen,
        onMinimize: widget.onMinimize,
        fullScreen: widget.fullScreen,
        onAction: (action) => _act(call.command(action)));
  }

  void _reportError(CallError? error) {
    if (error == null) return;
    final message = error.cause.describe(widget.l);
    if (error.source == CallErrorSource.audioSetup &&
        widget.onVoiceCallError != null) {
      widget.onVoiceCallError!(message);
    } else {
      context.toaster.show(message, kind: ToastKind.error);
    }
    ref
        .read(voiceCallOrchestratorProvider(widget.sessionId).notifier)
        .clearError();
  }

  void _act(CallViewCommand command) => runCallCommand(ref, command,
      onOpenConversation: widget.onOpenConversation);

  Future<void> _notify(IncomingCallDialog dialog) async {
    if (ref.read(androidWaitingOwnerProvider)?.attached == true ||
        ref.read(iosSystemCallsProvider) != null) {
      return;
    }
    final generation = _notificationGeneration;
    try {
      if (!await ref.read(notificationsReadyProvider.future) || !mounted) {
        return;
      }
      if (!_isIncoming(dialog.callId, generation)) return;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (await _windowFocused()) {
          _retryNotification(dialog.callId, generation);
          return;
        }
      }
      if (!mounted || !_isIncoming(dialog.callId, generation)) return;
      final plugin = ref.read(flutterLocalNotificationsPluginProvider);
      final peer =
          dialog.peerName.isEmpty ? widget.l.callPeerFallback : dialog.peerName;
      final body = widget.l.callIncomingNotification(peer);
      final id = Object.hash(widget.sessionId, dialog.callId) & 0x7fffffff;
      _notificationPlugin = plugin;
      _notificationId = id;
      _notificationWork = _notificationWork.then((_) async {
        if (!mounted || !_isIncoming(dialog.callId, generation)) return;
        await plugin.show(
            id: id,
            title: 'Mosh',
            body: body,
            notificationDetails: callNotificationDetails);
      }).catchError((Object _) {});
      await _notificationWork;
    } catch (_) {
      // The nonmodal call controls remain available without notifications.
    }
  }

  Future<bool> _windowFocused() async {
    try {
      return await windowManager.isFocused();
    } catch (_) {
      // An unavailable focus probe must not hide the incoming-call alert.
      return false;
    }
  }

  void _clearNotification() {
    ++_notificationGeneration;
    _notificationRetry?.cancel();
    _notificationRetry = null;
    final id = _notificationId;
    if (id == null) return;
    _notificationId = null;
    final plugin = _notificationPlugin!;
    // Cancellation follows any pending show, including after widget disposal.
    _notificationWork = _notificationWork
        .then((_) => plugin.cancel(id: id))
        .catchError((Object _) {});
  }

  bool _isIncoming(String id, int generation) {
    final state = ref.read(voiceCallOrchestratorProvider(widget.sessionId));
    final current = state.dialog;
    return generation == _notificationGeneration &&
        _notifiedCall == id &&
        !state.busy &&
        current is IncomingCallDialog &&
        !current.pending.answerPending &&
        current.callId == id;
  }

  void _retryNotification(String id, int generation) {
    if (!mounted || !_isIncoming(id, generation)) return;
    _notificationRetry?.cancel();
    _notificationRetry = Timer(const Duration(seconds: 1), () {
      _notificationRetry = null;
      if (!mounted || !_isIncoming(id, generation)) return;
      final current =
          ref.read(voiceCallOrchestratorProvider(widget.sessionId)).dialog;
      if (current is IncomingCallDialog) unawaited(_notify(current));
    });
  }
}

Future<Object?> startVoiceCall(WidgetRef ref, String sessionId) async {
  final alreadyInProgress =
      AppLocalizations.of(ref.context)!.callAlreadyInProgress;
  final result =
      await ref.read(voiceCallStartProvider.notifier).start(sessionId);
  return result is CallAlreadyInProgress ? alreadyInProgress : result;
}

Future<Object?> startVideoCall(WidgetRef ref, String sessionId) async {
  final label = AppLocalizations.of(ref.context)!.callAlreadyInProgress;
  final result = await ref
      .read(voiceCallStartProvider.notifier)
      .start(sessionId, video: true);
  return result is CallAlreadyInProgress ? label : result;
}
