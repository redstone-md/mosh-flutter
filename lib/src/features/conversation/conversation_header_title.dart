import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

/// The title of the Top bar card: who the conversation is with and, under
/// the name, how it is connected. Pressing it opens the conversation's
/// details.
class ConversationHeaderTitle extends StatelessWidget {
  const ConversationHeaderTitle({
    super.key,
    required this.name,
    required this.subtitle,
    this.onOpenDetails,
  });

  final String name;

  /// The line under the name; empty while nothing is known to say.
  final String subtitle;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.chatDetailsTitle,
      child: InkWell(
        key: const ValueKey('conversation-header-details'),
        borderRadius: MoshShapes.control,
        onTap: onOpenDetails,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
