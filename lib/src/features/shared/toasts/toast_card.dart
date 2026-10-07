import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'toast_motion.dart';
import 'toast_pose.dart';
import 'toaster.dart';

/// The toast surface at a [pose]: the body keeps its natural layout and
/// is cut to [ToastPose.height] when the stack folds it behind a shorter
/// toast. Reports the body's natural height through [onHeight].
class ToastCard extends StatelessWidget {
  const ToastCard({
    super.key,
    required this.entry,
    required this.pose,
    required this.layout,
    required this.onHeight,
    required this.onDismiss,
  });

  final ToastEntry entry;
  final ToastPose pose;
  final ToastLayout layout;
  final ValueChanged<double> onHeight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // One node per toast, so its text and its close button stay apart
    // from whatever the stack covers.
    Widget body = _MeasuredHeight(
      onHeight: onHeight,
      child: Opacity(opacity: pose.content, child: _body(context)),
    );
    if (pose.height case final height?) {
      body = SizedBox(
        height: height,
        child: ClipRect(
          child: OverflowBox(
            alignment: layout.origin,
            minHeight: 0,
            maxHeight: double.infinity,
            child: body,
          ),
        ),
      );
    }
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: MoshColors.bg3,
        borderRadius: MoshShapes.menu,
        border: Border.all(color: MoshColors.lineStrong),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(container: true, child: body),
      ),
    );
    if (pose.blur > 0.01) {
      card = ImageFiltered(
        imageFilter: ImageFilter.blur(
            sigmaX: pose.blur, sigmaY: pose.blur, tileMode: TileMode.decal),
        child: card,
      );
    }
    return Transform.translate(
      offset: Offset(0, pose.dy),
      child: Transform.scale(
        scale: pose.scale,
        alignment: layout.origin,
        child: Opacity(opacity: pose.opacity, child: _Bump(entry, card)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (icon, color) = switch (entry.kind) {
      ToastKind.info => (Icons.info_outline, MoshColors.fg2),
      ToastKind.success => (Icons.check_circle_outline, MoshColors.moss),
      ToastKind.error => (Icons.error_outline, MoshColors.danger),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              entry.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: MoshColors.fg1),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          container: true,
          button: true,
          label: l.toastDismiss,
          excludeSemantics: true,
          child: InkWell(
            onTap: onDismiss,
            borderRadius: MoshShapes.control,
            child: const FocusRing(
              radius: MoshShapes.control,
              child: SizedBox.square(
                dimension: 32,
                child: Icon(Icons.close, size: 16, color: MoshColors.fg3),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Pops a repeated toast with the entrance overshoot.
class _Bump extends StatelessWidget {
  const _Bump(this.entry, this.child);

  final ToastEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(entry.bumps),
        tween: Tween(
            begin: entry.bumps == 0 || MediaQuery.disableAnimationsOf(context)
                ? 1
                : ToastMotion.bumpScale,
            end: 1),
        duration: ToastMotion.open,
        curve: ToastMotion.bump,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: child,
      );
}

/// Reports its child's height after every layout that changes it.
class _MeasuredHeight extends SingleChildRenderObjectWidget {
  const _MeasuredHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMeasuredHeight renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasuredHeight extends RenderProxyBox {
  _RenderMeasuredHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
