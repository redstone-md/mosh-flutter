import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'start_hero.dart';
import 'start_list.dart';
import 'start_motion.dart';
import 'start_reveal.dart';

/// The start menu: the welcome beside, or above, the four ways to begin,
/// grouped by whether what they open is encrypted.
///
/// A wide pane puts the welcome left of the list. Narrower panes stack
/// them in one column, and a phone drops the mark so the actions come
/// first.
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

  /// From this pane width the welcome and the list sit side by side.
  static const twoColumnWidth = 860.0;

  /// Below this pane width the mark is dropped.
  static const markWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final list = StartReveal(
      delay: StartMotion.lineStagger * 2,
      child: StartActionList(actions: [
        StartAction(
          icon: Icons.chat_bubble_outline,
          accent: MoshColors.dmAccent,
          title: l.onboardTileChatTitle,
          description: l.onboardTileChatDesc,
          onTap: onPickChat,
        ),
        StartAction(
          icon: Icons.group_outlined,
          accent: MoshColors.groupAccent,
          title: l.onboardTileGroupTitle,
          description: l.onboardTileGroupDesc,
          onTap: onPickGroup,
        ),
        StartAction(
          icon: Icons.link,
          accent: MoshColors.fg2,
          title: l.onboardTileJoinTitle,
          description: l.onboardTileJoinDesc,
          onTap: onPickJoin,
        ),
        StartAction(
          icon: Icons.tag,
          accent: MoshColors.channelAccent,
          title: l.onboardTileChannelTitle,
          description: l.onboardTileChannelDesc,
          onTap: onPickChannel,
          encrypted: false,
        ),
      ]),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width >= twoColumnWidth) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Row(children: [
              const Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: 56),
                  child: StartHero(mark: true, titleSize: 40),
                ),
              ),
              Expanded(flex: 6, child: list),
            ]),
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StartHero(
                  mark: width >= markWidth, titleSize: width < 600 ? 26 : 30),
              const SizedBox(height: 28),
              list,
            ],
          ),
        ),
      );
    });
  }
}
