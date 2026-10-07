import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'start_motion.dart';

/// Plays [child] in once when it first mounts: it rises [StartMotion.revealRise],
/// unblurs and fades in after [delay]. Static under reduced motion.
class StartReveal extends StatefulWidget {
  const StartReveal(
      {super.key, this.delay = Duration.zero, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<StartReveal> createState() => _StartRevealState();
}

class _StartRevealState extends State<StartReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + StartMotion.reveal,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds / _controller.duration!.inMicroseconds,
      1,
      curve: StartMotion.ease,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) {
        // One tree shape at every frame, so the child keeps its state.
        final t = _progress.value;
        final blur = StartMotion.revealBlur * (1 - t);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, StartMotion.revealRise * (1 - t)),
            child: ImageFiltered(
              enabled: blur > 0.01,
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
