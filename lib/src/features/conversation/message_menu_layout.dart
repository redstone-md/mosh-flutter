part of 'message_context_menu.dart';

/// Place and grow from the cursor-facing corner, including a flipped menu.
class _MessageMenuLayout extends FlowDelegate {
  _MessageMenuLayout(this.position, this.padding, this.opacity, this.scale)
      : super(repaint: opacity);
  final Offset position;
  final EdgeInsets padding;
  final Animation<double> opacity;
  final Animation<double> scale;

  EdgeInsets get _insets => padding + const EdgeInsets.all(8);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      constraints.deflate(_insets).loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final child = context.getChildSize(0)!;
    final insets = _insets;
    final right = context.size.width - insets.right;
    final bottom = context.size.height - insets.bottom;
    final flipX = position.dx + child.width > right;
    final flipY = position.dy + child.height > bottom;
    // Insets can exceed a tiny viewport; keep clamp bounds ordered.
    final x = (flipX ? position.dx - child.width : position.dx)
        .clamp(insets.left, math.max(insets.left, right - child.width));
    final y = (flipY ? position.dy - child.height : position.dy)
        .clamp(insets.top, math.max(insets.top, bottom - child.height));
    final origin = Offset(flipX ? child.width : 0, flipY ? child.height : 0);
    context.paintChild(0,
        opacity: opacity.value,
        transform: Matrix4.identity()
          ..translateByDouble(x + origin.dx, y + origin.dy, 0, 1)
          ..scaleByDouble(scale.value, scale.value, 1, 1)
          ..translateByDouble(-origin.dx, -origin.dy, 0, 1));
  }

  @override
  bool shouldRepaint(_MessageMenuLayout oldDelegate) =>
      position != oldDelegate.position ||
      padding != oldDelegate.padding ||
      opacity != oldDelegate.opacity ||
      scale != oldDelegate.scale;
}
