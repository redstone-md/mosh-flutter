import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_diagnostics_content.dart';
import 'package:mosh/src/features/conversation/panel_head.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// The Connection status card: a summary a person can read, then the raw
/// values grouped by what they describe. It opens from the title bar and
/// from the details of a conversation.
///
/// At most one of [session], [channel] and [group] is given; with none the
/// panel says that no conversation is open. [error] is a runtime error
/// worded for the user, or null.
class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({
    super.key,
    this.session,
    this.channel,
    this.group,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.onClose,
  });

  final SessionSnapshot? session;
  final ChannelSnapshot? channel;
  final GroupSnapshot? group;
  final String? error;

  /// Whether a refresh is in flight: its button is off until it ends.
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: MoshColors.of(context).surfaceContainerLow,
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelHead(title: l.peerStatusTitle, actions: [
              IconButton(
                  tooltip: l.refreshStatus,
                  icon: const Icon(MoshIcons.refresh),
                  onPressed: refreshing ? null : onRefresh),
              IconButton(
                  tooltip: l.closePeerStatus,
                  icon: const Icon(MoshIcons.close),
                  onPressed: onClose),
            ]),
            Expanded(
              child: ConversationDiagnosticsContent(
                  session: session,
                  channel: channel,
                  group: group,
                  error: error),
            ),
          ],
        ),
      ),
    );
  }
}
