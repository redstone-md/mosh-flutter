import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'android_call_presentation.dart';
import 'call_video_renderer.dart';
import 'call_view_state.dart';
import 'mobile_call_frame.dart';
import 'voice_call_layer.dart';
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';

class MobileCallHost extends ConsumerStatefulWidget {
  const MobileCallHost(
      {super.key,
      required this.child,
      required this.call,
      required this.session,
      required this.video,
      required this.onAction,
      this.onOpenConversation});
  final Widget child;
  final CallViewState? call;
  final String? session;
  final CallVideoRenderer video;
  final Future<void> Function(CallViewCommand) onAction;
  final void Function(String session)? onOpenConversation;

  @override
  ConsumerState<MobileCallHost> createState() => _MobileCallHostState();
}

class _MobileCallHostState extends ConsumerState<MobileCallHost> {
  AndroidCallPresentation? _presentation;
  bool _expanded = true;
  bool _videoCall = false;
  String? _shownCall;

  @override
  void initState() {
    super.initState();
    _presentation = ref.read(androidCallPresentationProvider);
    _presentation?.bindImages(widget.video);
    _presentation?.onClose = (session, call) => unawaited(widget.onAction(
        CallViewCommand(
            sessionId: session, callId: call, action: CallViewAction.end)));
  }

  @override
  void dispose() {
    _presentation?.unbindImages(widget.video);
    _presentation?.onClose = null;
    super.dispose();
  }

  void _minimize() => setState(() => _expanded = false);

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    if (_shownCall != call?.callId) {
      _shownCall = call?.callId;
      _expanded = true;
      _videoCall = false;
    }
    _videoCall |= call?.media?.cameraRequested == true ||
        call?.media?.remoteCamera == true;
    _presentation?.update(call);
    final session = widget.session;
    return Stack(fit: StackFit.expand, children: [
      AndroidAppLockGate(
          interactive: session == null || !_expanded, child: widget.child),
      if (session != null)
        SafeArea(
            child: MobileCallFrame(
                key: ValueKey(_shownCall),
                expanded: _expanded,
                video: _videoCall,
                child: _controls(session))),
    ]);
  }

  Widget _controls(String session) => BackButtonListener(
        onBackButtonPressed: () async {
          if (!_expanded ||
              Navigator.of(context, rootNavigator: true).canPop()) {
            return false;
          }
          _minimize();
          return true;
        },
        child: VoiceCallLayer(
            key: ValueKey(session),
            sessionId: session,
            peerOverride: widget.call?.peer,
            l: AppLocalizations.of(context)!,
            compact: !_expanded,
            floating: !_expanded && _videoCall,
            video: widget.video,
            onMinimize: _minimize,
            onShowWindow:
                _expanded ? null : () => setState(() => _expanded = true),
            onOpenConversation: () {
              _minimize();
              widget.onOpenConversation?.call(session);
            }),
      );
}
