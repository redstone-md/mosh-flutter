import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_footer.dart';
import 'package:mosh/src/features/conversation/conversation_text_metrics.dart';

/// Reserves actual space for the time beside the last line or beneath it.
/// The body stays ordinary Text, preserving selection and exact clipboard text.
class ConversationMessageText extends StatelessWidget {
  const ConversationMessageText({
    super.key,
    required this.body,
    required this.footer,
  });

  final String body;
  final ConversationMessageFooter footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final style =
              DefaultTextStyle.of(context).style.merge(kMessageBodyStyle);
          final footerSize = footer.measure(context);
          final layout =
              _measure(context, style, constraints.maxWidth, footerSize);
          return SizedBox(
            width: layout.width,
            child: Stack(clipBehavior: Clip.none, children: [
              Padding(
                padding: EdgeInsets.only(
                    bottom: layout.below ? footerSize.height + 4 : 0),
                child: Text(body, style: style, textAlign: TextAlign.start),
              ),
              PositionedDirectional(end: 0, bottom: 0, child: footer),
            ]),
          );
        },
      );

  ({double width, bool below}) _measure(
      BuildContext context, TextStyle style, double maxWidth, Size footerSize) {
    final painter = conversationTextPainter(context, body, style,
        widthBasis: TextWidthBasis.longestLine)
      ..layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics();
    final reserved = footerSize.width == 0 ? 0.0 : footerSize.width + 8;
    final width = math.min(
        maxWidth,
        math.max(
            footerSize.width,
            (painter.width + (lines.length == 1 ? reserved : 0))
                .ceilToDouble()));
    // Layout again at the final width so rounding and explicit line breaks
    // cannot make a footer overlap the paragraph actually displayed.
    painter.layout(maxWidth: width);
    final lastLine = painter.computeLineMetrics().last;
    final below = lastLine.width + reserved > width ||
        footerSize.height > lastLine.height;
    painter.dispose();
    return (width: width, below: below && footerSize.height > 0);
  }
}
