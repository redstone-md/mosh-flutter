import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'call_media_view.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';
import 'call_view_state.dart';
import 'incoming_call_modal.dart';
import 'voice_call_layer.dart';
import 'main_window_call_host.dart';

/// App-level owner and presentation, mounted below the first-run gate and
/// above every route, including Settings. With a native call engine the call
/// shows in the main window (ADR 0052); without one it is a strip of controls
/// under the app.
class VoiceCallHost extends ConsumerStatefulWidget {
  const VoiceCallHost(
      {super.key, required this.child, this.onOpenConversation});
  final Widget child;
  final void Function(String sessionId)? onOpenConversation;

  @override
  ConsumerState<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends ConsumerState<VoiceCallHost> {
  AndroidWaitingOwner? _waiting;
  AndroidAppAccess? _access;
  late final NativeCallOwner? _owner = ref.read(nativeCallOwnerProvider);

  @override
  void initState() {
    super.initState();
    _access = ref.read(androidAppAccessProvider);
    _access?.addListener(_privacyChanged);
    final waiting = _waiting = ref.read(androidWaitingOwnerProvider);
    waiting?.platform.addListener(_privacyChanged);
    if (waiting != null) {
      waiting.calls.onAnswer = (session, call) async {
        if (!mounted || waiting.platform.state?.callInteractive != true) return;
        await ref
            .read(voiceCallOrchestratorProvider(session).notifier)
            .acceptCall(call);
      };
      unawaited(waiting.refresh().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _waiting?.calls.onAnswer = null;
    _waiting?.platform.removeListener(_privacyChanged);
    _access?.removeListener(_privacyChanged);
    super.dispose();
  }

  void _privacyChanged() {
    if (mounted) setState(() {});
  }

  /// Android closed the call's picture-in-picture: end the call it showed.
  void _end(String session, String call) {
    if (ref.read(voiceCallSessionProvider)?.sessionId != session) return;
    final provider = voiceCallOrchestratorProvider(session);
    final dialog = ref.read(provider).dialog;
    final end = CallViewCommand(
        sessionId: session, callId: call, action: CallViewAction.end);
    if (!end.matchesCall(session, dialog.callId,
        supersededCallId: dialog.supersededCallId)) {
      return;
    }
    unawaited(
        ref.read(provider.notifier).endCall(call, kCallDeclineReasonHangup));
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
            peerOverride: _access?.covered == true &&
                    _waiting?.platform.state?.showNamesWhenLocked != true
                ? 'Mosh'
                : null,
            muted: state.muted,
            media: state.nativeMedia == null
                ? null
                : CallMediaView.fromSnapshot(state.nativeMedia!,
                    cameraRequested: state.cameraRequested),
            audioReady: state.audioReady,
            audioFailed: state.audioFailed,
            busy: state.busy,
            occupancyConflict: state.occupancyConflict,
            error: state.error?.cause.describe(l),
          );
    final owner = _owner;
    final content = owner != null
        ? MainWindowCallHost(
            call: call,
            session: selected?.sessionId,
            video: owner.textures,
            onEnd: _end,
            onOpenConversation: widget.onOpenConversation,
            child: widget.child)
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

  Widget _strip(String sessionId, AppLocalizations l) => VoiceCallLayer(
        key: ValueKey(sessionId),
        sessionId: sessionId,
        l: l,
        onOpenConversation: () => widget.onOpenConversation?.call(sessionId),
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
