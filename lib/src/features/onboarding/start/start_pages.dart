import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'start_motion.dart';

/// Shows [pages][index] and keeps every other page mounted, so a step
/// keeps its typed text and created invite across a trip to the menu.
///
/// Changing [index] slides side by side: a page with a lower index leaves
/// to the left, a higher one to the right, each fading and blurring on
/// the way. The shown page sizes the stack; the leaving one is pinned to
/// its top edge until it has faded, painted in page order, so both read
/// through each other mid-slide. Instant under reduced motion.
class StartPages extends StatefulWidget {
  const StartPages({super.key, required this.index, required this.pages});

  final int index;
  final List<Widget> pages;

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
    // How far this page is from rest: 0 when shown and settled.
    final away = shown ? 1 - t : (i == leaving ? t : 1.0);
    final side = i < widget.index || (shown && i < (leaving ?? i)) ? -1 : 1;
    final blur = StartMotion.pageBlur * away;
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
                opacity: 1 - away,
                child: Transform.translate(
                  offset: Offset(side * StartMotion.pageShift * away, 0),
                  child: ImageFiltered(
                    enabled: blur > 0.01,
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: page,
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
}
