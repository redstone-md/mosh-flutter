import 'package:flutter/material.dart';
import 'package:mosh/src/features/shared/mosh_dialog_motion.dart';

/// Uses Flutter's modal route for focus, barriers, safe areas and theme capture.
Future<T?> showMoshDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? barrierLabel,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    _MoshDialogRoute<T>(
      context: context,
      builder: builder,
      barrierLabel: barrierLabel,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class _MoshDialogRoute<T> extends DialogRoute<T> {
  _MoshDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required this.reducedMotion,
    super.barrierLabel,
  }) : super(
          barrierDismissible: true,
          traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        );

  final bool reducedMotion;
  CurvedAnimation? _motion;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : MoshDialogMotion.openDuration;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : MoshDialogMotion.closeDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reducedMotion) return child;
    if (_motion?.parent != animation) {
      _motion?.dispose();
      _motion = CurvedAnimation(
        parent: animation,
        curve: MoshDialogMotion.curve,
        reverseCurve: MoshDialogMotion.curve.flipped,
      );
    }
    return MoshDialogTransition(animation: _motion!, child: child);
  }

  @override
  void dispose() {
    _motion?.dispose();
    super.dispose();
  }
}
