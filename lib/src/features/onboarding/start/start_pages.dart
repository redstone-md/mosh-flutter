import 'package:flutter/widgets.dart';

import 'start_motion.dart';

/// Shows [pages][index] and keeps every other page mounted, so a step
/// keeps its typed text and created invite across a trip to the menu.
///
/// Changing [index] fades through: the leaving page fades out first,
/// then the shown one fades in, each sliding a few pixels toward its side
/// (a lower index lies to the left). Every page is centred in a box at
/// least [minHeight] tall, so a short step and the tall menu share one
/// frame and nothing jumps when the shown page changes size. Instant
/// under reduced motion.
class StartPages extends StatefulWidget {
  const StartPages({
    super.key,
    required this.index,
    required this.pages,
    this.minHeight = 0,
  });

  final int index;
  final List<Widget> pages;

  /// The pane height pages centre in; the shown page may be taller.
  final double minHeight;

  @override
  State<StartPages> createState() => _StartPagesState();
}

class _StartPagesState extends State<StartPages>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: StartMotion.page, value: 1);
  late final Animation<double> _progress =
      CurvedAnimation(parent: _controller, curve: StartMotion.ease);
  int? _leaving;

  /// A page moves between the sizing slot and the overlay; its global key
  /// carries its state across.
  final List<GlobalKey> _keys = [];

  @override
  void didUpdateWidget(StartPages old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    _leaving = old.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
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
      builder: (context, _) {
        final t = _progress.value;
        final leaving = t < 1 ? _leaving : null;
        while (_keys.length < widget.pages.length) {
          _keys.add(GlobalKey());
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (i, page) in widget.pages.indexed)
              _page(i, page, leaving, t),
          ],
        );
      },
    );
  }

  /// Every page keeps one place in the tree; only its pose changes.
  Widget _page(int i, Widget page, int? leaving, double t) {
    final shown = i == widget.index;
    final visible = shown || i == leaving;
    // The leaving page clears out before the shown one arrives.
    final opacity = shown
        ? _fadeIn.transform(t)
        : (i == leaving ? 1 - _fadeOut.transform(t) : 0.0);
    final side = i < widget.index || (shown && i < (leaving ?? i)) ? -1 : 1;
    final body = KeyedSubtree(
      key: _keys[i],
      child: Offstage(
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: IgnorePointer(
            ignoring: !shown,
            child: ExcludeSemantics(
              excluding: !shown,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset:
                      Offset(side * StartMotion.pageShift * (1 - opacity), 0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: widget.minHeight),
                    child: Align(
                      child: SizedBox(width: double.infinity, child: page),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (shown) return body;
    return Positioned(top: 0, left: 0, right: 0, child: body);
  }

  static const _fadeOut = Interval(0, 0.4);
  static const _fadeIn = Interval(0.3, 1);
}
