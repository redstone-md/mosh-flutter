import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/state/call_presentation_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'android_call_presentation.dart';
import 'call_video_textures.dart';
import 'call_video_surfaces.dart';
import 'call_view_state.dart';
import 'call_window_parts.dart' show CallFullScreen;
import 'main_window_call_frame.dart';
import 'voice_call_layer.dart';

/// The call in the main window. Open it takes the window, and on desktop
/// can switch it to full screen; minimized it stays in sight in the form
/// [callPresentationProvider] gives it while the user browses chats. The
/// phone's strip stands above the app, the other forms lie over it, and the
/// desktop's plate is drawn by the title bar.
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
  final ValueListenable<CallVideoPictures> video;

  /// Ends the call whose picture-in-picture Android closed.
  final void Function(String session, String call) onEnd;
  final void Function(String session)? onOpenConversation;

  @override
  ConsumerState<MainWindowCallHost> createState() => _MainWindowCallHostState();
}

class _MainWindowCallHostState extends ConsumerState<MainWindowCallHost> {
  AndroidCallPresentation? _presentation;
  DesktopWindowController? _window;
  bool _enteredFullScreen = false;

  /// Keeps the one call layer, with the call's notification, as it moves
  /// between the strip's place and the frame over the app.
  final _layer = GlobalKey();

  @override
  void initState() {
    super.initState();
    _window = ref.read(desktopWindowControllerProvider);
    _presentation = ref.read(androidCallPresentationProvider);
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
    _presentation?.onClose = null;
    super.dispose();
  }

  void _minimize() => ref.read(callPresentationProvider.notifier).minimize();

  void _toggleFullScreen(DesktopWindowController window) {
    _enteredFullScreen = !window.fullScreen;
    unawaited(window.setFullScreen(_enteredFullScreen));
  }

  /// Full screen belongs to the open call that asked for it.
  void _leaveFullScreen() {
    if (!_enteredFullScreen) return;
    _enteredFullScreen = false;
    unawaited(_window?.setFullScreen(false));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(callPresentationProvider, (_, form) {
      if (form != CallForm.open) _leaveFullScreen();
    });
    _presentation?.update(widget.call);
    final session = widget.session;
    final form = session == null
        ? null
        : ref.watch(callPresentationProvider) ?? CallForm.open;
    // A session whose call has just gone keeps its layer, for the error it
    // may still report, and shows nothing.
    final covered = form == CallForm.open && widget.call != null;
    final strip = form == CallForm.strip && widget.call != null;
    final layer = form == null
        ? null
        : KeyedSubtree(key: _layer, child: _controls(session!, form));
    final content = Stack(fit: StackFit.expand, children: [
      _app(strip ? layer : null, covered: covered),
      // The tone of the open call, under the system's bars as well.
      if (covered)
        ColoredBox(color: MoshColors.of(context).surfaceContainerLowest),
      if (layer != null && !strip)
        SafeArea(
            child: MainWindowCallFrame(
                key: ValueKey(widget.call?.callId), form: form!, child: layer)),
    ]);
    // Android's PiP overlay collects the video surfaces above the whole app.
    return _presentation != null
        ? content
        : CallVideoSurfaceScope(
            onSurfaces: (surfaces) =>
                ref.read(nativeCallOwnerProvider)?.showVideoAt(surfaces),
            child: content);
  }

  /// The app, under the phone's [strip] when the call is one.
  Widget _app(Widget? strip, {required bool covered}) => Column(children: [
        // The strip stands above the app and takes the status bar's place.
        if (strip != null)
          ColoredBox(
              color: MoshColors.of(context).surfaceContainerLowest,
              child: SafeArea(bottom: false, child: strip)),
        Expanded(
            // Keyed, so the strip's coming and going never remounts the app.
            key: const ValueKey('app'),
            child: MediaQuery.removePadding(
                context: context,
                removeTop: strip != null,
                // Android's lock gate guards the chats under the call as well.
                child: AndroidAppLockGate(
                    interactive: !covered,
                    child: ExcludeFocus(
                        excluding: covered, child: widget.child)))),
      ]);

  Widget _controls(String session, CallForm form) {
    final window = _window;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (form != CallForm.open ||
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
          form: form,
          video: widget.video,
          fullScreen: window == null
              ? null
              : CallFullScreen(
                  window: window, onToggle: () => _toggleFullScreen(window)),
          onMinimize: _minimize,
          onOpen: ref.read(callPresentationProvider.notifier).open,
          onOpenConversation: () {
            _minimize();
            widget.onOpenConversation?.call(session);
          }),
    );
  }
}
