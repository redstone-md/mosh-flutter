import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/message_selection_actions.dart';

/// Keeps count and Cancel above the chat; desktop actions also live here.
class MessageSelectionBar extends StatelessWidget {
  const MessageSelectionBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onCancel,
  });

  final int count;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final compact = isMobileBreakpoint(context);
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: compact ? MoshSpace.s3 : MoshSpace.s5,
      title: Semantics(
        liveRegion: true,
        label: l.messagesSelected(count),
        excludeSemantics: true,
        child: Text(l.messagesSelected(count),
            style: Theme.of(context).textTheme.titleMedium),
      ),
      actions: [
        if (!compact) const MessageSelectionActions(),
        Padding(
          padding: EdgeInsetsDirectional.only(
              start: MoshSpace.s2, end: compact ? MoshSpace.s3 : MoshSpace.s5),
          child: TextButton(
              onPressed: busy ? null : onCancel, child: Text(l.dialogCancel)),
        ),
      ],
    );
  }
}
