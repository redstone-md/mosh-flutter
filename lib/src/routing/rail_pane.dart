import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/sessions/rail_item.dart' show kRailWidth;
import 'package:mosh/src/state/rail_layout_provider.dart';

/// Narrowest expanded chat list.
const double kRailMinWidth = 268;

/// Widest expanded chat list.
const double kRailMaxWidth = 480;

/// Room the conversation keeps beside a widened list.
const double kChatMinWidth = 320;

/// A drag that leaves the list narrower than this collapses it.
const double _kCollapseBelow = (kRailMinWidth + kRailCompactWidth) / 2;

/// One arrow-key step of the resize handle.
const double _kKeyStep = 16;

const Duration _kToggleDuration = Duration(milliseconds: 200);

/// The expanded list's width for a [chosen] width in a [total] wide row:
/// the window-relative default when nothing was chosen, and never so wide
/// that the conversation drops below [kChatMinWidth].
double railWidthFor(double? chosen, double total) {
  final widest =
      math.max(kRailMinWidth, math.min(kRailMaxWidth, total - kChatMinWidth));
  final width =
      chosen ?? (total * 0.28).roundToDouble().clamp(kRailMinWidth, kRailWidth);
  return width.clamp(kRailMinWidth, widest);
}

/// The desktop chat list beside the conversation, split by a handle that
/// resizes the list and collapses it to its avatar strip.
///
/// Dragging resizes live and saves once the drag ends; dragging past the
/// narrowest width snaps to the strip, and dragging out of the strip snaps
/// back. Collapsing and expanding animate unless motion is reduced. The
/// handle also takes arrow keys, Enter and a double click.
class RailPane extends ConsumerStatefulWidget {
  const RailPane({super.key, required this.rail, required this.chat});

  final Widget rail;
  final Widget chat;

  @override
  ConsumerState<RailPane> createState() => _RailPaneState();
}

class _RailPaneState extends ConsumerState<RailPane> {
  /// The width a drag started from, while one runs.
  double? _dragOrigin;
  double _dragDelta = 0;

  /// Whether the list was collapsed at the last build: collapsing and
  /// expanding animate, from any source, while resizes follow at once.
  bool? _wasCollapsed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final layout = ref.watch(railLayoutProvider);
          final total = constraints.maxWidth;
          final target = layout.collapsed
              ? kRailCompactWidth
              : railWidthFor(layout.width, total);
          final animate = _wasCollapsed != null &&
              _wasCollapsed != layout.collapsed &&
              !MediaQuery.disableAnimationsOf(context);
          _wasCollapsed = layout.collapsed;
          return TweenAnimationBuilder<double>(
            tween: Tween(end: target),
            duration: animate ? _kToggleDuration : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, width, _) =>
                _panes(context, layout, width, target, total),
          );
        },
      );

  Widget _panes(BuildContext context, RailLayout layout, double width,
      double target, double total) {
    final rail = SizedBox(
      width: width,
      // Laid out at its final width and clipped, so the list never
      // reflows mid-animation.
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: math.max(width, target),
          maxWidth: math.max(width, target),
          child:
              RailCompactScope(compact: layout.collapsed, child: widget.rail),
        ),
      ),
    );
    return Stack(
      children: [
        Row(children: [
          rail,
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: widget.chat),
        ]),
        PositionedDirectional(
          start: width - 4,
          top: 0,
          bottom: 0,
          width: 9,
          child: _ResizeHandle(
            layout: layout,
            width: target,
            dragging: _dragOrigin != null,
            onDragStart: () => setState(() {
              _dragOrigin = target;
              _dragDelta = 0;
            }),
            onDrag: (delta) => _drag(delta, total),
            onDragEnd: _endDrag,
            onStep: (step) => _step(layout, target, step, total),
            onToggle: _toggle,
          ),
        ),
      ],
    );
  }

  void _drag(double delta, double total) {
    final origin = _dragOrigin;
    if (origin == null) return;
    _dragDelta += delta;
    final raw = origin + _dragDelta;
    final current = ref.read(railLayoutProvider);
    final collapsed = raw < _kCollapseBelow;
    final next = collapsed
        ? current.copyWith(collapsed: true)
        : RailLayout(width: railWidthFor(raw, total), collapsed: false);
    if (next == current) return;
    ref.read(railLayoutProvider.notifier).preview(next);
  }

  void _endDrag() {
    if (_dragOrigin == null) return;
    setState(() => _dragOrigin = null);
    ref.read(railLayoutProvider.notifier).save();
  }

  void _step(RailLayout layout, double width, double step, double total) {
    final notifier = ref.read(railLayoutProvider.notifier);
    if (layout.collapsed) {
      if (step > 0) _toggle();
      return;
    }
    if (step < 0 && width <= kRailMinWidth) return _toggle();
    notifier.set(RailLayout(width: railWidthFor(width + step, total)));
  }

  void _toggle() {
    ref.read(railLayoutProvider.notifier).toggle();
  }
}

/// The 9px grip over the divider: a resize cursor, a line that lights up
/// while hovered, focused or dragged, and a slider for screen readers.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.layout,
    required this.width,
    required this.dragging,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onStep,
    required this.onToggle,
  });

  final RailLayout layout;
  final double width;
  final bool dragging;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onStep;
  final VoidCallback onToggle;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // The list sits at the end in right-to-left layouts, so a drag toward
    // the start widens it there.
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final collapsed = widget.layout.collapsed;
    final lit = _hovered || _focused || widget.dragging;
    return Semantics(
      slider: true,
      label: l.chatListResize,
      value: collapsed ? l.chatListCollapsed : '${widget.width.round()}',
      increasedValue: '${(widget.width + _kKeyStep).round()}',
      decreasedValue: '${(widget.width - _kKeyStep).round()}',
      onIncrease: () => widget.onStep(_kKeyStep),
      onDecrease: () => widget.onStep(-_kKeyStep),
      customSemanticsActions: {
        CustomSemanticsAction(
                label: collapsed ? l.chatListExpand : l.chatListCollapse):
            widget.onToggle,
      },
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (_, event) => _key(event, sign),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The edge follows the pointer from the press, slop included.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => widget.onDragStart(),
            onHorizontalDragUpdate: (details) =>
                widget.onDrag(details.primaryDelta! * sign),
            onHorizontalDragEnd: (_) => widget.onDragEnd(),
            onHorizontalDragCancel: widget.onDragEnd,
            onDoubleTap: widget.onToggle,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: lit ? 3 : 0,
                color: _focused ? MoshColors.focusRing : MoshColors.moss,
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _key(KeyEvent event, double sign) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft) {
      final toward = key == LogicalKeyboardKey.arrowRight ? 1.0 : -1.0;
      widget.onStep(_kKeyStep * toward * sign);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      widget.onToggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
