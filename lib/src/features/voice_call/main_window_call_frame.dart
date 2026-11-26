import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'call_view_state.dart' show CallForm;
import 'floating_call_view.dart';

/// Places the call over the main window: centered when open, in the upper
/// corner while it rings on the desktop, and with video a tile the user can
/// drag. Only the card and the tile intercept gestures; chats remain usable
/// underneath. The phone's strip is not laid over the window, and the plate
/// is the title bar's.
class MainWindowCallFrame extends StatefulWidget {
  const MainWindowCallFrame(
      {super.key, required this.form, required this.child});

  /// How far the card and the tile stand from the window's edges.
  static const double edge = 12;

  final CallForm form;
  final Widget child;

  @override
  State<MainWindowCallFrame> createState() => _MainWindowCallFrameState();
}

class _MainWindowCallFrameState extends State<MainWindowCallFrame> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    if (widget.form == CallForm.open) return Center(child: widget.child);
    if (widget.form != CallForm.tile) {
      return Align(
          alignment: AlignmentDirectional.topEnd,
          child: Padding(
              padding: const EdgeInsets.all(MainWindowCallFrame.edge),
              child: widget.child));
    }
    return LayoutBuilder(builder: (context, box) {
      final width =
          math.min(FloatingCallView.width(box.maxWidth), box.maxWidth);
      final height = FloatingCallView.height(context, width);
      final maxX = math.max(0.0, box.maxWidth - width);
      final maxY = math.max(0.0, box.maxHeight - height);
      final position = _position ??
          Offset(maxX - MainWindowCallFrame.edge, MainWindowCallFrame.edge);
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
