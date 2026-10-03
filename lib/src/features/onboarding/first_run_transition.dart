import 'package:flutter/material.dart';

import 'first_run_profile.dart';

/// Fade through zero before changing the step and its centered card height.
/// Only one form is mounted; outgoing controls cannot receive input or focus.
class SetupStepTransition extends StatefulWidget {
  const SetupStepTransition(
      {super.key, required this.step, required this.builder});

  final SetupStep step;
  final Widget Function(BuildContext, SetupStep) builder;

  @override
  State<SetupStepTransition> createState() => _SetupStepTransitionState();
}

class _SetupStepTransitionState extends State<SetupStepTransition>
    with SingleTickerProviderStateMixin {
  static const _exitDuration = Duration(milliseconds: 80);
  static const _enterDuration = Duration(milliseconds: 160);
  static const _easeOut = Cubic(.23, 1, .32, 1);
  late final _controller = AnimationController(
      vsync: this, animationBehavior: AnimationBehavior.preserve)
    ..addStatusListener(_settled);
  late SetupStep _visible = widget.step;
  Animation<double> _opacity = const AlwaysStoppedAnimation(1);
  Animation<Offset> _position = const AlwaysStoppedAnimation(Offset.zero);
  bool _exiting = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant SetupStepTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step == oldWidget.step) return;
    if (widget.step == _visible) {
      // A return during the exit restores this form from its current position.
      _exiting = false;
      _animate(1, Offset.zero, _enterDuration);
    } else if (!_exiting) {
      _exiting = true;
      final direction = (widget.step.index - _visible.index).sign;
      _animate(0, Offset(-.02 * direction, 0), _exitDuration);
    }
    // During an exit, keep fading and mount only the latest requested step.
  }

  void _animate(double opacity, Offset position, Duration duration) {
    final startOpacity = _opacity.value;
    final startPosition = _position.value;
    _controller.stop();
    _controller.duration = duration;
    _controller.value = 0;
    final curve = _controller.drive(CurveTween(curve: _easeOut));
    _opacity = Tween(begin: startOpacity, end: opacity).animate(curve);
    _position = Tween(begin: startPosition, end: position).animate(curve);
    _controller.forward();
  }

  void _settled(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      if (!_exiting) return;
      final direction = (widget.step.index - _visible.index).sign;
      _visible = widget.step;
      _exiting = false;
      _opacity = const AlwaysStoppedAnimation(0);
      _position = AlwaysStoppedAnimation(Offset(.02 * direction, 0));
      _animate(1, Offset.zero, _enterDuration);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _exiting || _controller.isAnimating;
    return IgnorePointer(
        ignoring: blocked,
        child: ExcludeFocus(
            excluding: blocked,
            child: ExcludeSemantics(
                excluding: _exiting,
                child: FadeTransition(
                    opacity: _opacity,
                    child: SlideTransition(
                        position: _reduceMotion
                            ? const AlwaysStoppedAnimation(Offset.zero)
                            : _position,
                        textDirection: Directionality.of(context),
                        child: KeyedSubtree(
                            key: ValueKey(_visible),
                            child: widget.builder(context, _visible)))))));
  }
}
