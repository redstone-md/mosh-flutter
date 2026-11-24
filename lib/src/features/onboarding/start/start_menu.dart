import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;

import 'start_list.dart';
import 'start_motion.dart';
import 'start_reveal.dart';

/// The Start menu card: what a new conversation can be. The four ways to
/// begin stand under their heading, grouped by who can read the conversation.
class StartMenu extends StatelessWidget {
  const StartMenu({
    super.key,
    required this.onPickChat,
    required this.onPickGroup,
    required this.onPickJoin,
    required this.onPickChannel,
  });

  final VoidCallback onPickChat;
  final VoidCallback onPickGroup;
  final VoidCallback onPickJoin;
  final VoidCallback onPickChannel;

  /// Width of the menu on the desktop: a 440 px row and the menu's padding.
  static const maxWidth = 472.0;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final l = AppLocalizations.of(context)!;
    final list = StartReveal(
      delay: StartMotion.lineStagger,
      child: StartActionList(actions: [
        StartAction(
          icon: MoshIcons.chat,
          accent: colors.primary,
          title: l.onboardTileChatTitle,
          description: l.onboardTileChatDesc,
          onTap: onPickChat,
        ),
        StartAction(
          icon: MoshIcons.group,
          accent: colors.secondary,
          title: l.onboardTileGroupTitle,
          description: l.onboardTileGroupDesc,
          onTap: onPickGroup,
        ),
        StartAction(
          icon: MoshIcons.link,
          accent: colors.onSurfaceVariant,
          title: l.onboardTileJoinTitle,
          description: l.onboardTileJoinDesc,
          onTap: onPickJoin,
        ),
        StartAction(
          icon: MoshIcons.tag,
          accent: colors.tertiary,
          title: l.onboardTileChannelTitle,
          description: l.onboardTileChannelDesc,
          onTap: onPickChannel,
          encrypted: false,
        ),
      ]),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A narrow window opens the menu as a screen of its own, and
            // the bar with the way back already names it.
            if (!isMobileBreakpoint(context))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    MoshSpace.s4, 0, MoshSpace.s4, MoshSpace.s2),
                child: StartReveal(
                  child: Semantics(
                    header: true,
                    child: Text('${l.startTitleLead} ${l.startTitleAccent}',
                        style: Theme.of(context).textTheme.headlineMedium),
                  ),
                ),
              ),
            list,
          ],
        ),
      ),
    );
  }
}
