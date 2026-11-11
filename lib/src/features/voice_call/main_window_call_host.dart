import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'android_call_presentation.dart';
import 'call_video_textures.dart';
import 'call_video_surfaces.dart';
import 'call_view_state.dart';
import 'main_window_call_frame.dart';
import 'voice_call_layer.dart';

/// The call in the main window, above the app. Expanded it takes the window,
/// and on desktop can switch it to full screen; minimized it is a mini view
/// while the user browses chats.
class MainWindowCallHost extends ConsumerStatefulWidget {
  const MainWindowCallHost(
      {super.key,
      required this.child,
      required this.call,
      required this.session,
      required this.video,
      required this.onEnd,
      this.onOpenConversation});
  final Widget child;
  final CallViewState? call;
  final String? session;
  final ValueListenable<CallVideoImages> video;

  /// Ends the call whose picture-in-picture Android closed.
  final void Function(String session, String call) onEnd;
  final void Function(String session)? onOpenConversation;

  @override
  ConsumerState<MainWindowCallHost> createState() => _MainWindowCallHostState();
}

class _MainWindowCallHostState extends ConsumerState<MainWindowCallHost> {
  AndroidCallPresentation? _presentation;
  DesktopWindowController? _window;
  bool _expanded = true;
  bool _videoCall = false;
  bool _enteredFullScreen = false;
  String? _shownCall;

  @override
  void initState() {
    super.initState();
    _window = ref.read(desktopWindowControllerProvider);
    _presentation = ref.read(androidCallPresentationProvider);
    _presentation?.bindImages(widget.video);
    _presentation?.onClose = (session, call) => widget.onEnd(session, call);
  }

  @override
  void didUpdateWidget(MainWindowCallHost old) {
    super.didUpdateWidget(old);
    if (widget.session == null) _leaveFullScreen();
  }

  @override
  void dispose() {
    _leaveFullScreen();
    _presentation?.unbindImages(widget.video);
    _presentation?.onClose = null;
    super.dispose();
  }

  void _minimize() {
    _leaveFullScreen();
    setState(() => _expanded = false);
  }

  void _toggleFullScreen(DesktopWindowController window) {
    _enteredFullScreen = !window.fullScreen;
    unawaited(window.setFullScreen(_enteredFullScreen));
  }

  /// Full screen belongs to the expanded call that asked for it.
  void _leaveFullScreen() {
    if (!_enteredFullScreen) return;
    _enteredFullScreen = false;
    unawaited(_window?.setFullScreen(false));
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    if (_shownCall != call?.callId) {
      _shownCall = call?.callId;
      // On desktop an incoming call does not take the window from what the
      // user is doing; it rings in the mini view.
      _expanded = _window == null || call?.phase != CallViewPhase.incoming;
      _videoCall = false;
      if (!_expanded) _leaveFullScreen();
    }
    _videoCall |= call?.media?.cameraRequested == true ||
        call?.media?.remoteCamera == true;
    _presentation?.update(call);
    final session = widget.session;
    final covered = session != null && _expanded;
    final window = _window;
    final content = Stack(fit: StackFit.expand, children: [
      // Android's lock gate guards the chats under the call as well.
      AndroidAppLockGate(
          interactive: !covered,
          child: ExcludeFocus(excluding: covered, child: widget.child)),
      if (covered) const Material(),
      if (session != null)
        SafeArea(
            child: Column(children: [
          if (covered && window != null)
            Material(
                type: MaterialType.transparency,
                child: Align(
                    alignment: Alignment.topRight,
                    child: _fullScreenButton(window))),
          Expanded(
              child: MainWindowCallFrame(
                  key: ValueKey(_shownCall),
                  expanded: _expanded,
                  video: _videoCall,
                  child: _controls(session))),
        ])),
    ]);
    // Android's PiP overlay collects the video surfaces above the whole app.
    return _presentation != null
        ? content
        : CallVideoSurfaceScope(
            onSurfaces: (surfaces) =>
                ref.read(nativeCallOwnerProvider)?.showVideoAt(surfaces),
            child: content);
  }

  Widget _fullScreenButton(DesktopWindowController window) => ListenableBuilder(
      listenable: window,
      builder: (context, _) {
        final l = AppLocalizations.of(context)!;
        return IconButton(
            tooltip: window.fullScreen
                ? l.nativeMenuExitFullScreen
                : l.nativeMenuEnterFullScreen,
            onPressed: () => _toggleFullScreen(window),
            icon: Icon(
                window.fullScreen ? Icons.fullscreen_exit : Icons.fullscreen));
      });

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
            onExpand: _expanded ? null : () => setState(() => _expanded = true),
            onOpenConversation: () {
              _minimize();
              widget.onOpenConversation?.call(session);
            }),
      );
}
