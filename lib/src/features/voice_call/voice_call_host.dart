import 'call_media_view.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'call_video_frame.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'call_video_renderer.dart';

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
  StreamSubscription<CallVideoFrame>? _frames;
  final _video = CallVideoRenderer();
  bool _expanded = true;
  String? _shownCall;
  late final bool _mobile = defaultTargetPlatform == TargetPlatform.android &&
      ref.read(nativeCallOwnerProvider) != null;

  @override
  void initState() {
    super.initState();
    _window = CallWindowCoordinator(ref.read(callWindowFactoryProvider), _act,
        (error) => debugPrint('Call window unavailable: ${error.runtimeType}'));
    _frames = ref.read(nativeCallOwnerProvider)?.frames.listen((frame) {
      if (_mobile) {
        unawaited(_video.receive(frame));
      } else {
        _window.presentFrame(frame);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_frames?.cancel());
    unawaited(_window.dispose());
    _video.dispose();
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
      case CallViewAction.camera:
        unawaited(notifier.toggleCamera());
      case CallViewAction.selectInput:
        unawaited(notifier.selectInput(command.deviceId));
      case CallViewAction.selectOutput:
        unawaited(notifier.selectOutput(command.deviceId));
      case CallViewAction.selectCamera:
        unawaited(notifier.selectCamera(command.deviceId));
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
            media: state.nativeMedia == null
                ? null
                : CallMediaView.fromSnapshot(state.nativeMedia!),
            audioReady: state.audioReady,
            audioFailed: state.audioFailed,
            busy: state.busy,
            occupancyConflict: state.occupancyConflict,
            language: Localizations.localeOf(context).languageCode,
            error: state.error?.cause.describe(l),
          );
    _window.update(call);
    _video.update(call);
    if (_shownCall != call?.callId) {
      _shownCall = call?.callId;
      _expanded = true;
    }
    final content = _mobile
        ? Stack(fit: StackFit.expand, children: [
            widget.child,
            if (selected != null)
              Align(
                  alignment:
                      _expanded ? Alignment.center : Alignment.bottomCenter,
                  child: SafeArea(child: _mobileCall(selected.sessionId, l))),
          ])
        : Column(children: [
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

  Widget _mobileCall(String sessionId, AppLocalizations l) =>
      BackButtonListener(
          onBackButtonPressed: () async {
            // Dialog routes get Back first; otherwise minimize presentation only.
            if (!_expanded ||
                Navigator.of(context, rootNavigator: true).canPop()) {
              return false;
            }
            setState(() => _expanded = false);
            return true;
          },
          child: VoiceCallLayer(
            key: ValueKey(sessionId),
            sessionId: sessionId,
            l: l,
            compact: !_expanded,
            video: _video,
            onShowWindow:
                _expanded ? null : () => setState(() => _expanded = true),
            onOpenConversation: () {
              setState(() => _expanded = false);
              widget.onOpenConversation?.call(sessionId);
            },
          ));

  Widget _strip(String sessionId, AppLocalizations l) => ValueListenableBuilder(
      valueListenable: _window.fallback,
      builder: (_, fallback, __) => VoiceCallLayer(
            key: ValueKey(sessionId),
            sessionId: sessionId,
            l: l,
            controlsInWindow: !fallback,
            onOpenConversation: () =>
                widget.onOpenConversation?.call(sessionId),
            onShowWindow: ref.read(callWindowFactoryProvider) == null
                ? null
                : () => unawaited(_window.show()),
            isCallWindowFocused: _window.isFocused,
            onVoiceCallError: (message) {
              if (message != null) {
                context.toaster.show(message, kind: ToastKind.error);
              }
            },
          ));
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
