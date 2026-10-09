import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';
import 'call_view_state.dart';
import 'call_window_coordinator.dart';
import 'incoming_call_modal.dart';
import 'voice_call_layer.dart';

/// App-level owner and presentation, mounted below the first-run gate and
/// above every route, including Settings. Call windows contain no audio owner.
class VoiceCallHost extends ConsumerStatefulWidget {
  const VoiceCallHost(
      {super.key, required this.child, this.onOpenConversation});
  final Widget child;
  final void Function(String sessionId)? onOpenConversation;

  @override
  ConsumerState<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends ConsumerState<VoiceCallHost> {
  late final CallWindowCoordinator _window;

  @override
  void initState() {
    super.initState();
    _window = CallWindowCoordinator(ref.read(callWindowFactoryProvider), _act,
        (error) => debugPrint('Call window unavailable: ${error.runtimeType}'));
  }

  @override
  void dispose() {
    unawaited(_window.dispose());
    super.dispose();
  }

  Future<void> _act(CallViewCommand command) async {
    final selected = ref.read(voiceCallSessionProvider);
    if (selected?.sessionId != command.sessionId) return;
    final provider = voiceCallOrchestratorProvider(command.sessionId);
    final state = ref.read(provider);
    if (!command.matchesCall(command.sessionId, state.dialog.callId,
            supersededCallId: state.dialog.supersededCallId) ||
        (state.busy && !command.action.availableWhileBusy)) {
      return;
    }
    final notifier = ref.read(provider.notifier);
    switch (command.action) {
      case CallViewAction.accept:
        await notifier.acceptCall(command.callId);
      case CallViewAction.decline:
        await notifier.declineCall(command.callId, kCallDeclineReasonUser);
      case CallViewAction.end:
        await notifier.endCall(command.callId, kCallDeclineReasonHangup);
      case CallViewAction.mute:
        notifier.toggleMute();
      case CallViewAction.openConversation:
        widget.onOpenConversation?.call(command.sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoPollProvider);
    final selected = ref.watch(voiceCallSessionProvider);
    final l = AppLocalizations.of(context)!;
    final state = selected == null
        ? null
        : ref.watch(voiceCallOrchestratorProvider(selected.sessionId));
    final call = state == null
        ? null
        : CallViewState.fromDialog(
            selected!.sessionId,
            state.dialog,
            fallback: l.callPeerFallback,
            muted: state.muted,
            audioReady: state.audioReady,
            audioFailed: state.audioFailed,
            busy: state.busy,
            occupancyConflict: state.occupancyConflict,
            language: Localizations.localeOf(context).languageCode,
            error: state.error?.cause.describe(l),
          );
    _window.update(call);
    final content = Column(children: [
      Expanded(child: widget.child),
      if (selected != null)
        SafeArea(top: false, child: _strip(selected.sessionId, l)),
    ]);
    return _CallHostOverlay(
      child: Padding(
        padding: EdgeInsets.only(
            bottom:
                selected == null ? 0 : MediaQuery.viewInsetsOf(context).bottom),
        // Keep the route mounted and consume the IME once while a call is shown.
        child: MediaQuery.removeViewInsets(
            context: context, removeBottom: selected != null, child: content),
      ),
    );
  }

  Widget _strip(String sessionId, AppLocalizations l) => VoiceCallLayer(
        key: ValueKey(sessionId),
        sessionId: sessionId,
        l: l,
        onOpenConversation: () => widget.onOpenConversation?.call(sessionId),
        onShowWindow: ref.read(callWindowFactoryProvider) == null
            ? null
            : () => unawaited(_window.show()),
        isCallWindowFocused: _window.isFocused,
        onVoiceCallError: (message) {
          if (message != null) {
            context.toaster.show(message, kind: ToastKind.error);
          }
        },
      );
}

/// MaterialApp.builder sits above the router's Overlay. The shared strip needs
/// its own Overlay ancestor for tooltips without adding a modal route.
class _CallHostOverlay extends StatefulWidget {
  const _CallHostOverlay({required this.child});
  final Widget child;

  @override
  State<_CallHostOverlay> createState() => _CallHostOverlayState();
}

class _CallHostOverlayState extends State<_CallHostOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(covariant _CallHostOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Overlay(clipBehavior: Clip.none, initialEntries: [_entry]);
}
