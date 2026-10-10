import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'desktop_window_controller.dart';

/// Existing window_manager caption artwork with keyboard and screen-reader
/// actions. The maximize geometry is also registered with the Windows runner.
class DesktopCaptionButtons extends StatefulWidget {
  const DesktopCaptionButtons(
      {super.key, required this.controller, required this.leading});
  final DesktopWindowController controller;
  final bool leading;

  @override
  State<DesktopCaptionButtons> createState() => _DesktopCaptionButtonsState();
}

class _DesktopCaptionButtonsState extends State<DesktopCaptionButtons> {
  final _maximizeKey = GlobalKey();
  Rect? _lastRegion;
  double? _lastRatio;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c.platform == TargetPlatform.macOS) {
      return SizedBox(width: widget.leading ? c.leadingInset : 0);
    }
    final layout = c.platform == TargetPlatform.windows
        ? ':minimize,maximize,close'
        : c.decorationLayout;
    final sides = layout.split(':');
    final index = widget.leading ? 0 : 1;
    final names = index < sides.length ? sides[index].split(',') : <String>[];
    if (c.platform == TargetPlatform.windows && !widget.leading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportRegion());
    }
    if (c.fullScreen) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final name in names)
        if (['minimize', 'maximize', 'close'].contains(name))
          _button(context, name),
    ]);
  }

  Widget _button(BuildContext context, String name) {
    final c = widget.controller;
    final l = AppLocalizations.of(context)!;
    final action = switch (name) {
      'minimize' => c.minimize,
      'maximize' => c.toggleMaximize,
      _ => c.close,
    };
    final label = switch (name) {
      'minimize' => l.nativeMenuMinimize,
      'maximize' => c.maximized ? l.windowRestore : l.windowMaximize,
      _ => l.dialogClose,
    };
    final caption = switch (name) {
      'minimize' => WindowCaptionButton.minimize(
          onPressed: action, brightness: Brightness.dark),
      'maximize' => c.maximized
          ? WindowCaptionButton.unmaximize(
              onPressed: action, brightness: Brightness.dark)
          : WindowCaptionButton.maximize(
              onPressed: action, brightness: Brightness.dark),
      _ => WindowCaptionButton.close(
          onPressed: action, brightness: Brightness.dark),
    };
    return _accessibleButton(
        label,
        action,
        FocusRing(
            radius: BorderRadius.zero,
            child: SizedBox(
                key: name == 'maximize' ? _maximizeKey : null,
                width: 46,
                height: 44,
                child: ColoredBox(
                    color: name == 'maximize' && c.maximizeHovered
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    child: Opacity(
                        opacity: c.focused ? 1 : 0.65, child: caption)))));
  }

  Widget _accessibleButton(
          String label, Future<void> Function() action, Widget child) =>
      Tooltip(
          message: label,
          child: Semantics(
              label: label,
              button: true,
              onTap: action,
              excludeSemantics: true,
              child: FocusableActionDetector(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent()
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                    unawaited(action());
                    return null;
                  })
                },
                child: child,
              )));

  void _reportRegion() {
    if (!mounted) return;
    final box = _maximizeKey.currentContext?.findRenderObject() as RenderBox?;
    final region =
        box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (region == _lastRegion && ratio == _lastRatio) return;
    _lastRegion = region;
    _lastRatio = ratio;
    unawaited(widget.controller.setMaximizeRegion(region, ratio));
  }
}
