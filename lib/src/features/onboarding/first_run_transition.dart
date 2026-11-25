import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'first_run_profile.dart';

const setupStepDuration = Duration(milliseconds: 240);
const setupStepExitDuration = Duration(milliseconds: 120);
const setupStepCurve = Cubic(.23, 1, .32, 1);

/// Places the wizard in its viewport: the step it opens with stands in the
/// middle, and from then on its top stays where it is, so the progress does
/// not move when a taller or a shorter step takes the place of the first.
/// A step too tall for the room under that top raises it, and one taller
/// than the window scrolls.
///
/// A change of [layout] (the viewport, the text size, the language) measures
/// anew.
class SetupStableLayout extends SingleChildRenderObjectWidget {
  const SetupStableLayout(
      {super.key,
      required this.layout,
      required this.viewportHeight,
      required super.child});
  final Object layout;
  final double viewportHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _StableLayout(layout, viewportHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _StableLayout).configure(layout, viewportHeight);
}

class _StableLayout extends RenderShiftedBox {
  _StableLayout(this._layout, this._viewportHeight) : super(null);
  Object _layout;
  double _viewportHeight;
  double? _top;

  void configure(Object layout, double viewportHeight) {
    if ((layout, viewportHeight) == (_layout, _viewportHeight)) return;
    _layout = layout;
    _viewportHeight = viewportHeight;
    _top = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final step = child!;
    step.layout(BoxConstraints(maxWidth: constraints.maxWidth),
        parentUsesSize: true);
    final room =
        (_viewportHeight - step.size.height).clamp(0.0, double.infinity);
    // A step that no longer fits under the top it was given (it opened
    // while still loading, say) pulls the top up just far enough, for good.
    final top = _top = (_top ?? room / 2).clamp(0.0, room);
    size = constraints.constrain(Size(constraints.maxWidth,
        (top + step.size.height).clamp(_viewportHeight, double.infinity)));
    (step.parentData! as BoxParentData).offset =
        Offset((size.width - step.size.width) / 2, top);
  }
}

/// Crossfades the step under the progress, which stays as it is. Visited steps
/// keep their state offstage, so returning to one restores its unfinished
/// input.
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
      Stack(alignment: Alignment.topCenter, children: [
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
                            child: TickerMode(
                                enabled: widget.active,
                                child: widget.child)))))));
  }
}
