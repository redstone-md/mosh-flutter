// VoiceCallLayer -- the pure renderer of the voice-call modals + overlay for
// one DM session. It owns NO call state of its own: it reads the dialog the
// orchestrator derived from the session snapshot (`voiceCallOrchestratorProvider
// .dialog`) and shows exactly that one modal, and it routes every control
// (accept / decline / hang up / mute) back to the orchestrator notifier.
//
// This is the parity-first port of React `private-dm-screen.tsx` L459-513,
// but where React drives the modals from a `useVoiceCallOrchestration`
// state machine that ALSO pumps audio frames, this layer is signaling-only:
// the audio transport is slice-3 work and lives in `voice_call_orchestrator
// .dart`. The layer is a `ConsumerStatefulWidget` placed in the DM body
// `Stack`; it routes through `showDialog` so the modals get modal-route
// focus + scrim for free (mirroring React's `.call-modal` fixed overlay).
//
// Why one route record and not four `_open*For` fields: a session carries at
// most one call (mosh-core builds all three call fields from one `CallState`
// phase), so the UI owes the user at most one modal. Tracking four separate
// "which modal is open" flags invited exactly the kind of re-mount / double
// open bug this rewrite removes -- a single `_openCallId` + `_openKind` is the
// one home for "what is on screen".

library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart' show windowManager;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_overlay.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/features/voice_call/outgoing_call_modal.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;
import 'package:mosh/src/state/notifications_provider.dart'
    show
        flutterLocalNotificationsPluginProvider,
        moshNotificationDetails,
        notificationsReadyProvider;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show
        CallError,
        CallErrorSource,
        ringtonePlayerProvider,
        voiceCallOrchestratorProvider;

/// The shape of call dialog currently shown (or none). A session carries at
/// most one call, so the layer shows at most one modal.
enum _CallKind { none, incoming, outgoing, active }

_CallKind _kindOf(CallDialog dialog) => switch (dialog) {
      NoCallDialog() => _CallKind.none,
      IncomingCallDialog() => _CallKind.incoming,
      OutgoingCallDialog() => _CallKind.outgoing,
      ActiveCallDialog() => _CallKind.active,
    };

/// Renders the voice-call modals/overlay for one DM session based purely on
/// the orchestrator's `dialog`. Place inside a `ProviderScope` + `Stack`.
class VoiceCallLayer extends ConsumerStatefulWidget {
  const VoiceCallLayer({
    super.key,
    required this.sessionId,
    required this.l,
    this.ringtone,
    this.onVoiceCallError,
  });

  /// The DM session this layer watches.
  final String sessionId;

  /// Localizations (callIncoming* / callOutgoing* / callActive* /
  /// callPeerFallback).
  final AppLocalizations l;

  /// The ringtone player for the incoming/outgoing modals. Defaults to
  /// [ringtonePlayerProvider], which is where the app binds one.
  final RingtonePlayer? ringtone;

  /// The owning DM screen's inline error setter for audio-setup failures.
  final void Function(String? message)? onVoiceCallError;

  @override
  ConsumerState<VoiceCallLayer> createState() => _VoiceCallLayerState();
}

class _VoiceCallLayerState extends ConsumerState<VoiceCallLayer> {
  // One record for "what modal is open", replacing the four `_open*For`
  // fields. `_openCallId`/`_openKind` are set synchronously when we decide to
  // open so a re-poll in the same frame cannot schedule a second open; the
  // post-frame callback re-checks them before calling `showDialog`.
  String? _openCallId;
  _CallKind? _openKind;
  BuildContext? _dialogContext;

  @override
  void didUpdateWidget(covariant VoiceCallLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      // The session we report against changed -- drop any open modal so we
      // do not surface a stale call from the previous session.
      _popOpen();
      _openCallId = null;
      _openKind = null;
      _dialogContext = null;
    }
  }

  RingtonePlayer _ringtone() =>
      widget.ringtone ?? ref.read(ringtonePlayerProvider);

  /// Closes the currently shown modal route if one is up.
  void _popOpen() {
    final ctx = _dialogContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
  }

  /// Opens the modal the [dialog] asks for, closing whatever is already open.
  /// No-op when the open modal already matches [dialog] (same call id + kind)
  /// so a re-poll that changes nothing does not re-mount the dialog.
  void _syncDialog(CallDialog dialog) {
    final openCallId = _openCallId;
    final openKind = _openKind;
    final newCallId = dialog.callId;
    final newKind = _kindOf(dialog);
    if (openCallId == newCallId && openKind == newKind) return;

    // Close the previously open modal (if its route is already up).
    if (openCallId != null || openKind != null) {
      _popOpen();
      _openCallId = null;
      _openKind = null;
      _dialogContext = null;
    }

    // Nothing to open.
    if (newKind == _CallKind.none) return;

    _openCallId = newCallId;
    _openKind = newKind;

    final peerLabel =
        dialog.peerName.isEmpty ? widget.l.callPeerFallback : dialog.peerName;

    // The OS toast is a one-shot: it fires only on the transition INTO an
    // incoming dialog (this `_syncDialog` returns early on every later
    // re-poll for the same call), mirroring React's "fire once per
    // pendingCallId change" dep-array.
    if (newKind == _CallKind.incoming) {
      _maybeNotifyIncomingCall(peerLabel);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The session / dialog may have moved on before this frame ran; the
      // synchronous `_openCallId`/`_openKind` we set above is the guard that
      // stops a stale scheduled open from winning.
      if (_openCallId != newCallId || _openKind != newKind) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          return _buildDialogFor(dialog, dialogContext, peerLabel);
        },
      ).then((_) {
        // Forget only the modal this route was. A pop that came from a
        // transition (outgoing -> active) resolves here after the
        // post-frame open already recorded the next modal; wiping that
        // record made the next re-poll push a second overlay.
        if (!mounted || _openCallId != newCallId || _openKind != newKind) {
          return;
        }
        _openCallId = null;
        _openKind = null;
        _dialogContext = null;
      });
    });
  }

  /// Builds the widget for [dialog] with control callbacks routed through the
  /// orchestrator notifier. A user action pops the modal first for snappy
  /// feedback; the notifier then refreshes the session, which flips `dialog`
  /// to the next shape (or none) and the layer reconciles on the next build.
  Widget _buildDialogFor(
    CallDialog dialog,
    BuildContext dialogContext,
    String peerLabel,
  ) {
    final notifier =
        ref.read(voiceCallOrchestratorProvider(widget.sessionId).notifier);

    if (dialog is IncomingCallDialog) {
      return IncomingCallModal(
        pending: dialog.pending,
        peerLabel: peerLabel,
        onAccept: () {
          Navigator.of(dialogContext).pop();
          notifier.acceptCall(dialog.callId);
        },
        onDecline: (reason) {
          Navigator.of(dialogContext).pop();
          notifier.declineCall(dialog.callId, reason);
        },
        ringtone: _ringtone(),
        l: widget.l,
      );
    }

    if (dialog is OutgoingCallDialog) {
      return OutgoingCallModal(
        call: dialog.call,
        peerLabel: peerLabel,
        onCancel: () {
          Navigator.of(dialogContext).pop();
          notifier.endCall(dialog.callId, kCallDeclineReasonHangup);
        },
        ringtone: _ringtone(),
        l: widget.l,
      );
    }

    if (dialog is ActiveCallDialog) {
      // The overlay reads live mute from the orchestrator itself (it is a
      // Consumer), so the mic icon tracks `toggleMute` without a re-mount.
      return CallOverlay(
        active: dialog.active,
        peerLabel: peerLabel,
        sessionId: widget.sessionId,
        onHangUp: () {
          Navigator.of(dialogContext).pop();
          notifier.endCall(dialog.callId, kCallDeclineReasonHangup);
        },
        l: widget.l,
      );
    }

    return const SizedBox.shrink();
  }

  /// Surfaces an orchestrator error: a call-control failure is transient
  /// feedback (a snack bar); an audio-setup failure killed the call, so it
  /// lands in the host conversation's error banner. Either way the layer
  /// clears the surfaced error so the orchestrator does not re-show it.
  void _surfaceError(CallError error) {
    if (!mounted) return;
    final message = error.cause.describe(AppLocalizations.of(context)!);
    if (error.source == CallErrorSource.callControl) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    } else {
      widget.onVoiceCallError?.call(message);
    }
    ref
        .read(voiceCallOrchestratorProvider(widget.sessionId).notifier)
        .clearError();
  }

  @override
  Widget build(BuildContext context) {
    final orc = ref.watch(voiceCallOrchestratorProvider(widget.sessionId));

    // One place owns call errors: the orchestrator. The layer only decides
    // how to show them, and clears them once shown.
    ref.listen<CallError?>(
      voiceCallOrchestratorProvider(widget.sessionId).select((s) => s.error),
      (_, error) {
        if (error == null) return;
        _surfaceError(error);
      },
    );

    _syncDialog(orc.dialog);

    // The layer renders nothing itself -- the modal routes through showDialog.
    return const SizedBox.shrink();
  }

  /// Fires the incoming-call OS toast, 1-в-1 with React's
  /// use-voice-call-orchestration.ts second `useEffect` (L250-275):
  /// gate on notificationsReady, check the window is unfocused, then
  /// `flutterLocalNotificationsPlugin.show`. Fire-and-forget (the effect's
  /// async IIFE); errors swallowed (the in-app IncomingCallModal is the
  /// user's signal regardless, mirrors React's `catch {}`).
  void _maybeNotifyIncomingCall(String displayName) {
    final ready = ref.read(notificationsReadyProvider).value ?? false;
    if (!ready) return;
    final plugin = ref.read(flutterLocalNotificationsPluginProvider);
    // The async IIFE: windowManager.isFocused() is async on Windows/macOS;
    // Linux is undocumented so the gate always notifies there (matches
    // React's "always notify on Linux" fallback). Mobile (Android/iOS) has
    // no window focus analog (AppLifecycleState is the analog and is a
    // separate Android slice), so always notify on mobile for now.
    () async {
      try {
        if (Platform.isWindows || Platform.isMacOS) {
          if (await windowManager.isFocused()) return;
        }
        // Linux + mobile: skip the focus check (no reliable analog in
        // window_manager; the Android slice wires AppLifecycleState).
        await plugin.show(
          id: displayName.hashCode.abs(),
          title: 'Mosh',
          body: 'Incoming call from $displayName',
          notificationDetails: moshNotificationDetails,
        );
      } catch (_) {
        // Notification host unavailable; the in-app IncomingCallModal is
        // the user's signal (mirrors React's catch {}).
      }
    }();
  }
}

/// Starts a voice call for [sessionId] via the bridge facade. Exposed as
/// a top-level helper so the DM AppBar's start-call IconButton can trigger
/// a call without the layer owning the AppBar (the layer is body-local;
/// the AppBar lives on DmScreen). Returns the thrown error so the caller
/// can surface a SnackBar on its own `BuildContext` (avoiding the
/// use_build_context_synchronously lint for this fire-and-refresh helper).
Future<Object?> startVoiceCall(WidgetRef ref, String sessionId) async {
  try {
    await ref.read(bridgeFacadeProvider).callStart(sessionId: sessionId);
    // Force a re-fetch from the gateway so the session snapshot reflects the
    // new outgoing call; the orchestrator (which watches this provider)
    // then derives the OutgoingCallDialog.
    ref.invalidate(activeSessionProvider(sessionId));
    return null;
  } catch (e) {
    return e;
  }
}
