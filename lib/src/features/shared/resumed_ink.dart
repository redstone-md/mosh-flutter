import 'package:flutter/widgets.dart';

/// Remounts [child] when its tickers resume after a covering route or an
/// offstage branch muted them.
///
/// Ink started by the tap that opened the route freezes with the muted
/// tickers and would otherwise finish fading only after the return, so the
/// control flashes its pressed state. A fresh subtree has no ink.
class ResumedInk extends StatefulWidget {
  const ResumedInk({super.key, required this.child});

  final Widget child;

  @override
  State<ResumedInk> createState() => _ResumedInkState();
}

class _ResumedInkState extends State<ResumedInk> {
  bool _ticking = true;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticking = TickerMode.valuesOf(context).enabled;
    if (ticking && !_ticking) _generation++;
    _ticking = ticking;
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_generation), child: widget.child);
}
