import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;

/// The Conversation empty card: what a conversation shows when it has
/// nothing to show. It says what will appear here and what to do next, in
/// the app's own voice and without a drawing. When loading [failed] the
/// title is in the error colour, the line says what went wrong, and
/// [onAction] under [actionLabel] offers to try again.
class ConversationNotice extends StatelessWidget {
  const ConversationNotice({
    super.key,
    required this.title,
    required this.line,
    this.failed = false,
    this.quiet = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String line;
  final bool failed;

  /// The Search empty card: a search that found nothing says so in smaller
  /// type and closer to the header, as the feed is still there behind it.
  final bool quiet;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The widest the words run before they wrap.
  static const double measure = 360;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    // Scrolls when large text does not fit a short or narrow pane.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            vertical: quiet ? MoshSpace.s8 : MoshSpace.s12,
            horizontal:
                isMobileBreakpoint(context) ? MoshSpace.s3 : MoshSpace.s5),
        child: ConstrainedBox(
          // No wider than the measure, and 32 px clear of each edge.
          constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - MoshSpace.s16)
                  .clamp(0.0, measure)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                textAlign: TextAlign.center,
                style: (quiet ? text.titleSmall : text.titleMedium)!
                    .copyWith(color: failed ? colors.error : colors.onSurface)),
            const SizedBox(height: MoshSpace.s1),
            Text(line,
                textAlign: TextAlign.center,
                style: (quiet ? text.bodySmall : text.bodyMedium)!
                    .copyWith(color: colors.onSurfaceVariant)),
            if (actionLabel case final label?) ...[
              const SizedBox(height: MoshSpace.s2),
              OutlinedButton(onPressed: onAction, child: Text(label)),
            ],
          ]),
        ),
      ),
    );
  }
}
