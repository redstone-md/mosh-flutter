import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'toast_card.dart';
import 'toast_motion.dart';
import 'toast_pose.dart';
import 'toaster.dart';

/// Below the desktop titlebar, which is 44px tall.
const double _kTopInset = 56;

/// Above the phone composer.
const double _kBottomInset = 88;

const double _kMaxWidth = 360;

/// Shows the app's [Toaster] over [child] in one stack: hanging below the
/// titlebar on desktop, above the composer on phones.
///
/// The newest toast leads and older ones fold behind it. Hovering fans
/// the stack out and holds its timers until the pointer leaves the fanned
/// column. A swipe toward the edge, or the close button, dismisses. Every
/// arrival is announced to screen readers; errors interrupt.
class ToastHost extends ConsumerStatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ToastHost> createState() => _ToastHostState();
}

class _Slot {
  _Slot(this.entry);

  ToastEntry entry;
  ToastPose? leavingFrom;
  bool toEdge = false;
  bool swiped = false;
  double drag = 0;
  bool dragging = false;
}

class _ToastHostState extends ConsumerState<ToastHost> {
  /// The toaster of the scope above, followed if that scope's container
  /// is replaced.
  Toaster? _attached;
  Toaster get _toaster => _attached!;

  /// Newest first, including toasts still animating out.
  final List<_Slot> _slots = [];
  final Map<int, double> _heights = {};
  final Map<int, ToastPose> _poses = {};
  final Set<Timer> _removals = {};
  bool _spread = false;

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach(Toaster toaster) {
    if (identical(toaster, _attached)) return;
    _detach();
    _slots.clear();
    _heights.clear();
    _poses.clear();
    _spread = false;
    _attached = toaster..addListener(_sync);
    _sync(rebuild: false);
  }

  /// Toasts belong to the host that shows them.
  void _detach() {
    for (final timer in _removals) {
      timer.cancel();
    }
    _removals.clear();
    _attached
      ?..removeListener(_sync)
      ..paused = false
      ..clear();
    _attached = null;
  }

  void _sync({bool rebuild = true}) {
    final shown = _toaster.toasts;
    final ids = {for (final entry in shown) entry.id};
    for (final slot in _slots) {
      if (slot.leavingFrom != null || ids.contains(slot.entry.id)) continue;
      _leave(slot);
    }
    final active = <_Slot>[];
    for (final entry in shown) {
      final index = _slots.indexWhere((s) => s.entry.id == entry.id);
      if (index >= 0) {
        // A repeat is news again for a screen reader.
        if (_slots[index].entry.bumps != entry.bumps) _announce(entry);
        active.add(_slots[index]..entry = entry);
      } else {
        active.add(_Slot(entry));
        _announce(entry);
      }
    }
    // Leaving toasts finish behind the ones that stay.
    final leaving = _slots.where((s) => s.leavingFrom != null).toList();
    _slots
      ..clear()
      ..addAll(active)
      ..addAll(leaving);
    if (shown.isEmpty) _setSpread(false, rebuild: rebuild);
    if (rebuild && mounted) setState(() {});
  }

  void _leave(_Slot slot) {
    final from = _poses[slot.entry.id] ?? const ToastPose();
    final active = _active();
    slot
      ..leavingFrom = from
      ..toEdge = slot.swiped ||
          (!_spread && active.isNotEmpty && active.first == slot);
    late final Timer timer;
    timer = Timer(ToastMotion.close, () {
      _removals.remove(timer);
      if (!mounted) return;
      setState(() {
        _slots.remove(slot);
        _heights.remove(slot.entry.id);
        _poses.remove(slot.entry.id);
      });
    });
    _removals.add(timer);
  }

  void _announce(ToastEntry entry) {
    if (!mounted) return;
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      entry.message,
      Directionality.of(context),
      assertiveness: entry.kind == ToastKind.error
          ? Assertiveness.assertive
          : Assertiveness.polite,
    ));
  }

  List<_Slot> _active() => [
        for (final slot in _slots)
          if (slot.leavingFrom == null) slot
      ];

  void _setSpread(bool value, {bool rebuild = true}) {
    if (_spread == value) return;
    _spread = value;
    _toaster.paused = value;
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _attach(ref.watch(toasterProvider));
    final mobile = MediaQuery.sizeOf(context).width <= 580;
    final layout = ToastLayout(
      away: mobile ? -1 : 1,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    final padding = MediaQuery.paddingOf(context);
    final width = math.min(_kMaxWidth, MediaQuery.sizeOf(context).width - 32);
    return Stack(children: [
      widget.child,
      if (_slots.isNotEmpty)
        Positioned(
          top: mobile ? null : padding.top + _kTopInset,
          bottom: mobile ? padding.bottom + _kBottomInset : null,
          left: 0,
          right: 0,
          child: Center(
            child: MouseRegion(
              onEnter: (_) => _setSpread(true),
              onExit: (_) => _setSpread(false),
              child: SizedBox(
                width: width,
                height: _extent(layout),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final slot in _slots.reversed) _slot(slot, layout),
                  ],
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  /// The stack's footprint: the hover target and the room it fans into.
  double _extent(ToastLayout layout) {
    final active = _active();
    if (active.isEmpty) return 0;
    final front = _heights[active.first.entry.id] ?? 0;
    if (!_spread) return front + ToastMotion.peek * (active.length - 1);
    return active.fold(
            0.0,
            (sum, s) =>
                sum + (_heights[s.entry.id] ?? 0) + ToastMotion.spreadGap) -
        ToastMotion.spreadGap;
  }

  ToastPose _target(_Slot slot, ToastLayout layout) {
    if (slot.leavingFrom case final from?) {
      return layout.leaving(from, toEdge: slot.toEdge);
    }
    final active = _active();
    final depth = active.indexOf(slot);
    final own = _heights[slot.entry.id];
    final ToastPose pose;
    if (_spread) {
      var offset = 0.0;
      for (final newer in active.take(depth)) {
        offset += (_heights[newer.entry.id] ?? 0) + ToastMotion.spreadGap;
      }
      pose = layout.spread(offset, own);
    } else {
      pose = layout.collapsed(
          math.min(depth, 2), _heights[active.first.entry.id], own);
    }
    return pose.shifted(slot.drag);
  }

  Duration _duration(_Slot slot, ToastLayout layout) {
    if (layout.reduceMotion || slot.dragging) return Duration.zero;
    if (slot.leavingFrom != null) return ToastMotion.close;
    return _spread ? ToastMotion.spread : ToastMotion.open;
  }

  Widget _slot(_Slot slot, ToastLayout layout) {
    final id = slot.entry.id;
    final target = _target(slot, layout);
    return Positioned(
      key: ValueKey(id),
      top: layout.away > 0 ? 0 : null,
      bottom: layout.away > 0 ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: slot.leavingFrom != null,
        child: GestureDetector(
          onVerticalDragStart: (_) => setState(() => slot.dragging = true),
          onVerticalDragUpdate: (details) =>
              setState(() => slot.drag = _resist(slot.drag, details, layout)),
          onVerticalDragEnd: (details) => _release(slot, details, layout),
          child: TweenAnimationBuilder<ToastPose>(
            tween: ToastPoseTween(begin: layout.entering, end: target),
            duration: _duration(slot, layout),
            curve: ToastMotion.ease,
            builder: (context, pose, _) {
              _poses[id] = pose;
              return ToastCard(
                entry: slot.entry,
                pose: pose,
                layout: layout,
                onHeight: (height) {
                  if (!mounted || _heights[id] == height) return;
                  setState(() => _heights[id] = height);
                },
                onDismiss: () => _toaster.dismiss(id),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Follows the finger toward the edge; resists the other way.
  double _resist(double drag, DragUpdateDetails details, ToastLayout layout) {
    final next = drag + details.delta.dy;
    final towardEdge = next * layout.away < 0;
    return towardEdge ? next : drag + details.delta.dy * 0.2;
  }

  void _release(_Slot slot, DragEndDetails details, ToastLayout layout) {
    final velocity = (details.primaryVelocity ?? 0) * -layout.away;
    final distance = slot.drag * -layout.away;
    setState(() => slot.dragging = false);
    if (distance > ToastMotion.swipeDistance ||
        velocity > ToastMotion.swipeVelocity) {
      slot.swiped = true;
      _toaster.dismiss(slot.entry.id);
      return;
    }
    setState(() => slot.drag = 0);
  }
}
