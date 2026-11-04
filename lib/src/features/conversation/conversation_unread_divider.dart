import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The bar above the first message that arrived since the user last viewed
/// the conversation, full width like a date divider's band.
class ConversationUnreadDivider extends StatelessWidget {
  const ConversationUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 5),
          color: MoshColors.bg2,
          alignment: Alignment.center,
          child: Text(
            AppLocalizations.of(context)!.chatUnreadDivider,
            style: const TextStyle(fontSize: 12, color: MoshColors.fg2),
          ),
        ),
      );
}
