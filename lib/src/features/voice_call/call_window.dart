import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'call_notice.dart';
import 'call_video_stage.dart';
import 'call_video_textures.dart';
import 'call_button.dart' show CallControl;
import 'call_window_parts.dart';

/// How long the buttons of a call stay over its video without a pointer
/// move, a touch or a key.
const kCallControlsRest = Duration(seconds: 3);

/// The Call window card: an open call takes the whole window, on the lowest
/// tone. A voice call puts the person in the middle; with video the picture
/// takes that place, as large as the window lets it be without cutting it,
/// and the name moves to a plate in the corner. The buttons stay on their
/// dock at the bottom, with a [notice] just above them.
///
/// While the other side's video is showing, everything laid over it but
/// your own camera leaves after [kCallControlsRest] without a pointer move,
/// a touch or a key, and any of those brings it back. It stays while a
/// notice is shown, while the keyboard's focus is on a button and while the
/// pointer is over the dock, and whenever the system reports assistive
/// navigation. A muted microphone keeps a mark in the corner.
class CallWindow extends StatefulWidget {
  const CallWindow({
    super.key,
    required this.label,
    required this.peer,
    required this.status,
    required this.controls,
    this.statusFontFeatures,
    this.failed = false,
    this.muted = false,
    this.notice,
    this.video,
    this.remoteCamera = false,
    this.onOpenConversation,
    this.onMinimize,
    this.fullScreen,
  });

  /// What a screen reader calls the window.
  final String label;
  final String peer;
  final String status;
  final List<FontFeature>? statusFontFeatures;

  /// The call's buttons, drawn larger on a phone held upright.
  final List<CallControl> controls;

  /// Whether [status] says that the call cannot go on as it is.
  final bool failed;
  final bool muted;
  final CallNotice? notice;
  final ValueListenable<CallVideoPictures>? video;

  /// Whether the other side's camera is on, before its first frame.
  final bool remoteCamera;
  final VoidCallback? onOpenConversation;

  /// Leaves the open call for its minimized view; Escape does the same.
  final VoidCallback? onMinimize;

  /// The desktop's full screen switch; a phone's call has the whole screen.
  final CallFullScreen? fullScreen;

  @override
  State<CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<CallWindow> {
  final _controls = FocusNode(
      debugLabel: 'call controls', canRequestFocus: false, skipTraversal: true);
  Timer? _rest;
  bool _rested = false;
  bool _mayRest = false;
  bool _overDock = false;

  /// Whether the last thing the user did was press a key.
  bool _byKeyboard = false;

  @override
  void initState() {
    super.initState();
    widget.video?.addListener(_sync);
    HardwareKeyboard.instance.addHandler(_key);
    _sync();
  }

  @override
  void didUpdateWidget(CallWindow old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video) {
      old.video?.removeListener(_sync);
      widget.video?.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    _rest?.cancel();
    widget.video?.removeListener(_sync);
    HardwareKeyboard.instance.removeHandler(_key);
    _controls.dispose();
    super.dispose();
  }

  /// The rest is counted only over the other side's video without a notice.
  void _sync() {
    final may = widget.video?.value.remote != null && widget.notice == null;
    if (may == _mayRest) return;
    _mayRest = may;
    _stir();
  }

  /// A pointer move, a touch or a key: the controls are back for a while.
  void _stir() {
    _rest?.cancel();
    _rest = _mayRest
        ? Timer(kCallControlsRest, () => setState(() => _rested = true))
        : null;
    if (_rested) setState(() => _rested = false);
  }

  bool _key(KeyEvent event) {
    _byKeyboard = true;
    _stir();
    return false;
  }

  void _pointer(PointerEvent event) {
    _byKeyboard = false;
    _stir();
  }

  /// The focus holds the controls while the keyboard is what moves it: it
  /// stays on a button after the user has gone back to the pointer.
  bool get _focused => _byKeyboard && _controls.hasFocus;

  bool _hidden(BuildContext context) =>
      _rested &&
      _mayRest &&
      !_overDock &&
      !_focused &&
      !MediaQuery.accessibleNavigationOf(context);

  void _dock(bool over) {
    if (over != _overDock) setState(() => _overDock = over);
  }

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final video = widget.video;
    return ModalFocusTrap(
      // Escape minimizes an open call; it never ends one.
      onEscape: widget.onMinimize,
      autofocus: true,
      child: Semantics(
        label: widget.label,
        container: true,
        child: SizedBox.expand(
          child: Material(
            color: colors.surfaceContainerLowest,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _pointer,
              onPointerMove: _pointer,
              onPointerHover: _pointer,
              child: video == null
                  ? _layers(context, const CallVideoPictures())
                  : ValueListenableBuilder(
                      valueListenable: video,
                      builder: (context, pictures, _) =>
                          _layers(context, pictures)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layers(BuildContext context, CallVideoPictures pictures) {
    final video = widget.video;
    final staged = video != null &&
        CallVideoStage.shows(pictures, remoteCamera: widget.remoteCamera);
    final hidden = _hidden(context);
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MoshMotion.effectsDefault.duration;
    return Stack(fit: StackFit.expand, children: [
      if (video != null)
        Center(
            child: CallVideoStage(
                video: video,
                peer: widget.peer,
                remoteCamera: widget.remoteCamera)),
      // Always in its place, so muting does not move the controls after it.
      AnimatedOpacity(
          opacity: widget.muted && hidden ? 1 : 0,
          duration: fade,
          curve: MoshMotion.effectsDefault.curve,
          child: const CallMutedMark()),
      AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: fade,
        // A screen reader still finds the buttons of a call left alone.
        alwaysIncludeSemantics: true,
        curve: MoshMotion.effectsDefault.curve,
        child: IgnorePointer(
          ignoring: hidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: Focus(
                focusNode: _controls,
                onFocusChange: (_) => setState(() {}),
                child: _controlsOver(context, staged: staged)),
          ),
        ),
      ),
    ]);
  }

  /// Everything laid over the stage: the top row, the person of a voice
  /// call and the foot with the notice and the dock.
  Widget _controlsOver(BuildContext context, {required bool staged}) {
    final form = CallWindowForm.of(context);
    return Column(children: [
      CallTopRow(
          form: form,
          who: staged
              ? CallWhoPlate(
                  peer: widget.peer,
                  status: widget.status,
                  statusFontFeatures: widget.statusFontFeatures,
                  onTap: widget.onOpenConversation)
              : null,
          onMinimize: widget.onMinimize,
          fullScreen: widget.fullScreen),
      Expanded(
          child: LayoutBuilder(
              builder: (context, box) => Column(children: [
                    Expanded(
                        child: staged
                            ? const SizedBox.shrink()
                            : CallWho(
                                form: form,
                                peer: widget.peer,
                                status: widget.status,
                                statusFontFeatures: widget.statusFontFeatures,
                                failed: widget.failed,
                                onTap: widget.onOpenConversation)),
                    _foot(form, box.biggest),
                  ]))),
    ]);
  }

  /// The foot at the bottom of the [room] under the top row. A window too
  /// low for the notice and the dock scales them down together.
  Widget _foot(CallWindowForm form, Size room) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: room.height),
      child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomCenter,
          child: SizedBox(
              width: room.width,
              child: CallFoot(
                  form: form,
                  notice: widget.notice,
                  onDockHover: _dock,
                  controls: widget.controls))));
}
