import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'desktop_window_controller.dart';

/// The window buttons of the Window title bar card: minimize, maximize and
/// close as tall as the bar, with square corners as the system draws them.
/// The maximize geometry is also registered with the Windows runner.
class DesktopCaptionButtons extends StatefulWidget {
  const DesktopCaptionButtons(
      {super.key, required this.controller, required this.leading});
  final DesktopWindowController controller;
  final bool leading;

  /// The buttons the window has on its [leading] or trailing side, in order.
  /// macOS draws its own, so it has none here.
  static List<String> names(DesktopWindowController c,
      {required bool leading}) {
    if (c.platform == TargetPlatform.macOS) return const [];
    final layout = c.platform == TargetPlatform.windows
        ? ':minimize,maximize,close'
        : c.decorationLayout;
    final sides = layout.split(':');
    final index = leading ? 0 : 1;
    return [
      if (index < sides.length)
        for (final name in sides[index].split(','))
          if (const ['minimize', 'maximize', 'close'].contains(name)) name,
    ];
  }

  @override
  State<DesktopCaptionButtons> createState() => _DesktopCaptionButtonsState();
}

class _DesktopCaptionButtonsState extends State<DesktopCaptionButtons> {
  final _maximizeKey = GlobalKey();
  Rect? _lastRegion;
  Rect? _lastButtonsRegion;
  double? _lastRatio;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c.platform == TargetPlatform.macOS) {
      return SizedBox(width: widget.leading ? c.leadingInset : 0);
    }
    if (c.platform == TargetPlatform.windows && !widget.leading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportRegion());
    }
    if (c.fullScreen) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final name
          in DesktopCaptionButtons.names(c, leading: widget.leading))
        _button(context, name),
    ]);
  }

  Widget _button(BuildContext context, String name) {
    final c = widget.controller;
    final l = AppLocalizations.of(context)!;
    final (action, label, icon) = switch (name) {
      'minimize' => (c.minimize, l.nativeMenuMinimize, MoshIcons.minimize),
      'maximize' => c.maximized
          ? (c.toggleMaximize, l.windowRestore, MoshIcons.restore)
          : (c.toggleMaximize, l.windowMaximize, MoshIcons.maximize),
      _ => (c.close, l.dialogClose, MoshIcons.close),
    };
    return _CaptionButton(
      key: name == 'maximize' ? _maximizeKey : null,
      label: label,
      icon: icon,
      onPressed: () => unawaited(action()),
      closes: name == 'close',
      // Windows takes the pointer over maximize for its snap layouts and
      // reports the hover instead.
      hovered: name == 'maximize' && c.maximizeHovered,
      windowFocused: c.focused,
    );
  }

  void _reportRegion() {
    if (!mounted) return;
    final box = _maximizeKey.currentContext?.findRenderObject() as RenderBox?;
    final region =
        box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
    final buttons = context.findRenderObject() as RenderBox;
    final buttonsRegion = buttons.localToGlobal(Offset.zero) & buttons.size;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (region == _lastRegion &&
        buttonsRegion == _lastButtonsRegion &&
        ratio == _lastRatio) {
      return;
    }
    _lastRegion = region;
    _lastButtonsRegion = buttonsRegion;
    _lastRatio = ratio;
    unawaited(widget.controller
        .setMaximizeRegion(region, ratio, buttonsRegion: buttonsRegion));
  }
}

/// One window button: 48 px wide and as tall as the bar. Hover and press are
/// the state layers of any control; close turns to the error colour under
/// the pointer, as the system's does.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed,
      required this.closes,
      required this.hovered,
      required this.windowFocused});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool closes;
  final bool hovered;
  final bool windowFocused;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final hovered = _hovered || widget.hovered;
    final alarm = widget.closes && hovered;
    final ink = alarm ? colors.onError : colors.onSurfaceVariant;
    return Tooltip(
      message: widget.label,
      child: Semantics(
        label: widget.label,
        button: true,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: Material(
          color: alarm
              ? colors.error
              : hovered
                  ? MoshState.tint(colors.onSurface, MoshState.hover)
                  : Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            onHover: (hovered) => setState(() => _hovered = hovered),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            overlayColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.pressed)
                    ? MoshState.tint(ink, MoshState.pressed)
                    : null),
            child: FocusRing(
              radius: BorderRadius.zero,
              child: SizedBox(
                width: MoshSpace.s12,
                height: MoshSpace.s10,
                child: Icon(widget.icon,
                    size: MoshSpace.s4,
                    color: widget.windowFocused
                        ? ink
                        : MoshState.tint(ink, MoshState.disabledContent)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
