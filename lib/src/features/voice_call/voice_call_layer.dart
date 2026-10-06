import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart' show windowManager;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
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
    this.onShowWindow,
    this.isCallWindowFocused,
  });

  final String sessionId;
  final AppLocalizations l;
  final void Function(String? message)? onVoiceCallError;
  final VoidCallback? onOpenConversation;
  final VoidCallback? onShowWindow;
  final Future<bool> Function()? isCallWindowFocused;

  @override
  ConsumerState<VoiceCallLayer> createState() => _VoiceCallLayerState();
}

class _VoiceCallLayerState extends ConsumerState<VoiceCallLayer> {
  String? _notifiedCall;
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
    if (dialog is! IncomingCallDialog ||
        state.busy ||
        dialog.callId != _notifiedCall) {
      _clearNotification();
    }
    if (dialog is IncomingCallDialog && _notifiedCall != dialog.callId) {
      _notifiedCall = dialog.callId;
      unawaited(_notify(dialog));
    }
    final call = CallViewState.fromDialog(
      widget.sessionId,
      dialog,
      fallback: widget.l.callPeerFallback,
      muted: state.muted,
      audioReady: state.audioReady,
      audioFailed: state.audioFailed,
      busy: state.busy,
      language: Localizations.localeOf(context).languageCode,
      error: state.error?.cause.describe(widget.l),
    );
    if (call == null) return const SizedBox.shrink();
    return CallView(
        call: call,
        compact: true,
        onShowWindow: widget.onShowWindow,
        onAction: (action) => _act(call.command(action)));
  }

  void _reportError(CallError? error) {
    if (error == null) return;
    final message = error.cause.describe(widget.l);
    if (error.source == CallErrorSource.audioSetup &&
        widget.onVoiceCallError != null) {
      widget.onVoiceCallError!(message);
    } else {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
    ref
        .read(voiceCallOrchestratorProvider(widget.sessionId).notifier)
        .clearError();
  }

  void _act(CallViewCommand command) {
    final state = ref.read(voiceCallOrchestratorProvider(widget.sessionId));
    if ((state.busy && !command.action.availableWhileBusy) ||
        state.dialog.callId != command.callId) {
      return;
    }
    final notifier =
        ref.read(voiceCallOrchestratorProvider(widget.sessionId).notifier);
    final id = command.callId;
    switch (command.action) {
      case CallViewAction.accept:
        unawaited(notifier.acceptCall(id));
      case CallViewAction.decline:
        unawaited(notifier.declineCall(id, kCallDeclineReasonUser));
      case CallViewAction.end:
        unawaited(notifier.endCall(id, kCallDeclineReasonHangup));
      case CallViewAction.mute:
        notifier.toggleMute();
      case CallViewAction.openConversation:
        widget.onOpenConversation?.call();
    }
  }

  Future<void> _notify(IncomingCallDialog dialog) async {
    try {
      if (!await ref.read(notificationsReadyProvider.future) || !mounted) {
        return;
      }
      if (!_isIncoming(dialog.callId)) return;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (await windowManager.isFocused()) return;
        if (await widget.isCallWindowFocused?.call() ?? false) return;
      }
      if (!mounted || !_isIncoming(dialog.callId)) return;
      final plugin = ref.read(flutterLocalNotificationsPluginProvider);
      final peer =
          dialog.peerName.isEmpty ? widget.l.callPeerFallback : dialog.peerName;
      final body = widget.l.callIncomingNotification(peer);
      final id = Object.hash(widget.sessionId, dialog.callId) & 0x7fffffff;
      _notificationPlugin = plugin;
      _notificationId = id;
      _notificationWork = _notificationWork.then((_) async {
        if (!mounted || !_isIncoming(dialog.callId)) return;
        await plugin.show(
            id: id,
            title: 'Mosh',
            body: body,
            notificationDetails: moshNotificationDetails);
      }).catchError((Object _) {});
      await _notificationWork;
    } catch (_) {
      // The nonmodal call controls remain available without notifications.
    }
  }

  void _clearNotification() {
    final id = _notificationId;
    if (id == null) return;
    _notificationId = null;
    final plugin = _notificationPlugin!;
    // Cancellation follows any pending show, including after widget disposal.
    _notificationWork = _notificationWork
        .then((_) => plugin.cancel(id: id))
        .catchError((Object _) {});
  }

  bool _isIncoming(String id) {
    final state = ref.read(voiceCallOrchestratorProvider(widget.sessionId));
    final current = state.dialog;
    return _notifiedCall == id &&
        !state.busy &&
        current is IncomingCallDialog &&
        current.callId == id;
  }
}

Future<Object?> startVoiceCall(WidgetRef ref, String sessionId) async {
  final result =
      await ref.read(voiceCallStartProvider.notifier).start(sessionId);
  if (result is CallAlreadyInProgress && ref.context.mounted) {
    return AppLocalizations.of(ref.context)!.callAlreadyInProgress;
  }
  return result;
}
