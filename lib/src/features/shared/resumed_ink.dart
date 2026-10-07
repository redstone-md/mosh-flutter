import 'package:flutter/widgets.dart';

/// Remounts the ink control from [builder] when its tickers resume after a
/// covering route or an offstage branch muted them.
///
/// Ink started by the tap that opened the route freezes with the muted
/// tickers and would otherwise finish fading only after the return, so the
/// control flashes its pressed state. A fresh subtree has no ink. The focus
/// node outlives the remount, so keyboard focus comes back to the control.
class ResumedInk extends StatefulWidget {
  const ResumedInk({super.key, required this.builder});

  /// Builds the control around [focusNode], which it must pass to its
  /// InkWell.
  final Widget Function(FocusNode focusNode) builder;

  @override
  State<ResumedInk> createState() => _ResumedInkState();
}

class _ResumedInkState extends State<ResumedInk> {
  final _focusNode = FocusNode(debugLabel: 'resumed-ink');
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
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
      key: ValueKey(_generation), child: widget.builder(_focusNode));
}
