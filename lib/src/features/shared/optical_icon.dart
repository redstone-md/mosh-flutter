import 'package:flutter/material.dart';

/// An icon adjusted by an optical offset so directional or asymmetric glyphs
/// (play triangles, alert icons) appear visually centered in circular or
/// square frames.
class OpticalIcon extends StatelessWidget {
  const OpticalIcon({
    super.key,
    required this.icon,
    this.offset = const Offset(1.5, 0),
    this.size,
    this.color,
  });

  /// The icon glyph.
  final IconData icon;

  /// Directional offset. Defaults to +1.5px X for right-pointing play arrows.
  final Offset offset;

  /// Icon size.
  final double? size;

  /// Icon color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Icon(icon, size: size, color: color),
    );
  }
}
