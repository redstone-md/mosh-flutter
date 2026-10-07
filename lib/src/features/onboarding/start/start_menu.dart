import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

import 'start_card.dart';
import 'start_hero.dart';
import 'start_motion.dart';
import 'start_reveal.dart';

/// Below this width the hero drops its illustration.
const double _kIllustratedWidth = 760;

/// The start menu: the welcome hero over the four ways to begin.
///
/// The cards sit four in a row on a wide pane, two by two on a narrower
/// one and stack on a phone.
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

  static int columnsFor(double width) => width >= 1000
      ? 4
      : width >= 520
          ? 2
          : 1;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cards = <StartCard Function(bool)>[
      (compact) => StartCard(
            icon: Icons.chat_bubble_outline,
            title: l.onboardTileChatTitle,
            description: l.onboardTileChatDesc,
            onTap: onPickChat,
            compact: compact,
          ),
      (compact) => StartCard(
            icon: Icons.group_outlined,
            title: l.onboardTileGroupTitle,
            description: l.onboardTileGroupDesc,
            onTap: onPickGroup,
            compact: compact,
          ),
      (compact) => StartCard(
            icon: Icons.link,
            title: l.onboardTileJoinTitle,
            description: l.onboardTileJoinDesc,
            onTap: onPickJoin,
            compact: compact,
          ),
      (compact) => StartCard(
            icon: Icons.tag,
            title: l.onboardTileChannelTitle,
            description: l.onboardTileChannelDesc,
            onTap: onPickChannel,
            compact: compact,
          ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StartHero(illustrated: width >= _kIllustratedWidth),
          SizedBox(height: width >= _kIllustratedWidth ? 40 : 28),
          _CardGrid(columns: columnsFor(width), cards: cards),
        ],
      );
    });
  }
}

/// Rows of equally tall cards, revealed one after another.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.columns, required this.cards});

  final int columns;

  /// Builds a card, compact or not.
  final List<StartCard Function(bool compact)> cards;

  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < cards.length; start += columns) {
      final row = cards.skip(start).take(columns).toList();
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, card) in row.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: StartReveal(
                  delay: StartMotion.lineStagger * 2 +
                      StartMotion.cardStagger * (start + i),
                  child: card(columns == 1),
                ),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: _gap),
          row,
        ],
      ],
    );
  }
}
