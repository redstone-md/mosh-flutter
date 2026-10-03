import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'first_run_profile.dart';

const setupStepDuration = Duration(milliseconds: 240);
const setupStepExitDuration = Duration(milliseconds: 120);
const setupStepCurve = Cubic(.23, 1, .32, 1);

/// Reserve the first step's natural height without retaining expanded import
/// panels. A viewport, text-scale or locale change starts a new measurement.
class SetupStableLayout extends SingleChildRenderObjectWidget {
  const SetupStableLayout(
      {super.key,
      required this.layout,
      required this.reserve,
      required this.maximumBaseline,
      required super.child});
  final Object layout;
  final double reserve;
  final double maximumBaseline;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _StableLayout(layout, reserve, maximumBaseline);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _StableLayout)
          .configure(layout, reserve, maximumBaseline);
}

class _StableLayout extends RenderProxyBox {
  _StableLayout(this._layout, this._reserve, this._maximumBaseline);
  Object _layout;
  double _reserve;
  double _maximumBaseline;
  double? _baseline;

  void configure(Object value, double reserve, double maximumBaseline) {
    if ((value, reserve, maximumBaseline) ==
        (_layout, _reserve, _maximumBaseline)) {
      return;
    }
    _layout = value;
    _reserve = reserve;
    _maximumBaseline = maximumBaseline;
    _baseline = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_baseline == null) {
      child!.layout(constraints, parentUsesSize: true);
      final natural = child!.size.height;
      final room = (_maximumBaseline - natural).clamp(0.0, _reserve);
      _baseline = natural + room;
    }
    child!.layout(
        constraints.copyWith(
            minHeight:
                _baseline!.clamp(constraints.minHeight, constraints.maxHeight)),
        parentUsesSize: true);
    size = child!.size;
  }
}

/// Give the glass artwork a little depth independently of the form's slide.
class SetupArtworkMotion extends StatelessWidget {
  const SetupArtworkMotion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_ArtworkMotion>();
    return ScaleTransition(
        scale: motion != null && !MediaQuery.disableAnimationsOf(context)
            ? Tween(begin: .97, end: 1.0).animate(motion.opacity)
            : const AlwaysStoppedAnimation(1.0),
        child: child);
  }
}

class _ArtworkMotion extends InheritedWidget {
  const _ArtworkMotion({required this.opacity, required super.child});
  final Animation<double> opacity;

  @override
  bool updateShouldNotify(_ArtworkMotion oldWidget) =>
      opacity != oldWidget.opacity;
}

/// Crossfade one region within the persistent setup frame. Visited panels keep
/// their state offstage, so returning to a step restores its unfinished input.
class SetupStepTransition extends StatefulWidget {
  const SetupStepTransition(
      {super.key, required this.step, required this.builder});

  final SetupStep step;
  final Widget Function(BuildContext, SetupStep) builder;

  @override
  State<SetupStepTransition> createState() => _SetupStepTransitionState();
}

class _SetupStepTransitionState extends State<SetupStepTransition> {
  late final _initial = widget.step;
  late final _visited = <SetupStep>{widget.step};
  int _direction = 1;

  @override
  void didUpdateWidget(covariant SetupStepTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step == oldWidget.step) return;
    _direction = (widget.step.index - oldWidget.step.index).sign;
    _visited.add(widget.step);
  }

  @override
  Widget build(BuildContext context) =>
      Stack(alignment: Alignment.center, children: [
        for (final step in [
          ..._visited.where((step) => step != widget.step),
          widget.step
        ])
          _SetupPanel(
              key: ValueKey(step),
              active: step == widget.step,
              animateEntrance: step != _initial,
              direction: _direction,
              child: widget.builder(context, step)),
      ]);
}

class _SetupPanel extends StatefulWidget {
  const _SetupPanel(
      {super.key,
      required this.active,
      required this.animateEntrance,
      required this.direction,
      required this.child});
  final bool active;
  final bool animateEntrance;
  final int direction;
  final Widget child;

  @override
  State<_SetupPanel> createState() => _SetupPanelState();
}

class _SetupPanelState extends State<_SetupPanel>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this)
    ..addStatusListener(_settled);
  Animation<double> _opacity = const AlwaysStoppedAnimation(1);
  Animation<Offset> _position = const AlwaysStoppedAnimation(Offset.zero);

  @override
  void initState() {
    super.initState();
    if (!widget.animateEntrance) return;
    _opacity = const AlwaysStoppedAnimation(0);
    _position = AlwaysStoppedAnimation(Offset(.03 * widget.direction, 0));
    _animate(1, Offset.zero, setupStepDuration);
  }

  @override
  void didUpdateWidget(covariant _SetupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _animate(1, Offset.zero, setupStepDuration);
    } else {
      _animate(0, Offset(-.03 * widget.direction, 0), setupStepExitDuration);
    }
  }

  void _animate(double opacity, Offset position, Duration duration) {
    final startOpacity = _opacity.value;
    final startPosition = _position.value;
    _controller.stop();
    _controller.duration = duration;
    _controller.value = 0;
    final curve = _controller.drive(CurveTween(curve: setupStepCurve));
    _opacity = Tween(begin: startOpacity, end: opacity).animate(curve);
    _position = Tween(begin: startPosition, end: position).animate(curve);
    _controller.forward();
  }

  void _settled(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final blocked = !widget.active || _controller.isAnimating;
    return Offstage(
        offstage: !widget.active && !_controller.isAnimating,
        child: IgnorePointer(
            ignoring: blocked,
            child: ExcludeFocus(
                excluding: blocked,
                child: ExcludeSemantics(
                    excluding: !widget.active,
                    child: FadeTransition(
                        opacity: _opacity,
                        child: SlideTransition(
                            position: reduced
                                ? const AlwaysStoppedAnimation(Offset.zero)
                                : _position,
                            textDirection: Directionality.of(context),
                            child: _ArtworkMotion(
                                opacity: _opacity,
                                child: TickerMode(
                                    enabled: widget.active,
                                    child: widget.child))))))));
  }
}
