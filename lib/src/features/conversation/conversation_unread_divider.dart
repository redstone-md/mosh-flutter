import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Unread divider card: a rule across the feed, named in the accent,
/// above the first message that arrived since the user last viewed the
/// conversation.
class ConversationUnreadDivider extends StatelessWidget {
  const ConversationUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MoshSpace.s2),
          child: Row(
            spacing: MoshSpace.s3,
            children: [
              const Expanded(child: Divider()),
              Text(
                AppLocalizations.of(context)!.chatUnreadDivider,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium!
                    .copyWith(color: MoshColors.of(context).primary),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
      );
}
