import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Only the mini-window intercepts gestures; chats remain usable underneath.
class MobileCallFrame extends StatefulWidget {
  const MobileCallFrame(
      {super.key,
      required this.expanded,
      required this.video,
      required this.child});
  final bool expanded, video;
  final Widget child;

  @override
  State<MobileCallFrame> createState() => _MobileCallFrameState();
}

class _MobileCallFrameState extends State<MobileCallFrame> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    if (widget.expanded) return Center(child: widget.child);
    if (!widget.video) {
      return Align(alignment: Alignment.topCenter, child: widget.child);
    }
    return LayoutBuilder(builder: (context, box) {
      final width = math.min(196.0, box.maxWidth);
      final height = width * 9 / 16 + 48;
      final maxX = math.max(0.0, box.maxWidth - width);
      final maxY = math.max(0.0, box.maxHeight - height);
      final position = _position ?? Offset(maxX - 12, 12);
      final clamped =
          Offset(position.dx.clamp(0, maxX), position.dy.clamp(0, maxY));
      return Stack(children: [
        Positioned(
          left: clamped.dx,
          top: clamped.dy,
          width: width,
          height: height,
          child: GestureDetector(
              onPanUpdate: (drag) {
                // Several pointer updates can arrive before the next build.
                final current = _position ?? clamped;
                setState(() => _position = Offset(
                    (current.dx.clamp(0, maxX) + drag.delta.dx).clamp(0, maxX),
                    (current.dy.clamp(0, maxY) + drag.delta.dy)
                        .clamp(0, maxY)));
              },
              child: widget.child),
        )
      ]);
    });
  }
}
