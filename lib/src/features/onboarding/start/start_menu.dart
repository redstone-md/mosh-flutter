import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
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

  /// From this content width (the pane less its side padding) the
  /// welcome and the list sit side by side.
  static const twoColumnWidth = 860.0;

  /// Below this content width the mark is dropped.
  static const markWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final l = AppLocalizations.of(context)!;
    final list = StartReveal(
      delay: StartMotion.lineStagger * 2,
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
