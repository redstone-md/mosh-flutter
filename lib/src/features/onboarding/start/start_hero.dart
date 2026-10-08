import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'start_motion.dart';
import 'start_reveal.dart';

/// The start menu's welcome: the Mosh mark when [mark], the title and
/// what Mosh protects.
class StartHero extends StatelessWidget {
  const StartHero({super.key, required this.mark, required this.titleSize});

  final bool mark;
  final double titleSize;

  /// The mark's height beside a two-column menu.
  static const markHeight = 150.0;

  /// `hero.png` holds its art 119px into a 706px-tall canvas; pulling it
  /// back by that share lines the art up with the title.
  static const _markInset = 119 / 706;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final markHeight = titleSize >= 36 ? StartHero.markHeight : 104.0;
    final lines = <Widget>[
      if (mark)
        Transform.translate(
          offset: Offset(-markHeight * _markInset, 0),
          child: ExcludeSemantics(
            child: Image.asset(
              'assets/start/hero.png',
              height: markHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      Semantics(
        header: true,
        child: Text(
          '${l.startTitleLead} ${l.startTitleAccent}',
          style: text.displaySmall?.copyWith(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              height: 1.15,
              letterSpacing: -0.4,
              color: MoshColors.fg1),
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          l.startSubtitle,
          style: text.bodyLarge
              ?.copyWith(color: MoshColors.fg2, height: 1.55, fontSize: 15),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) SizedBox(height: mark && i == 1 ? 20 : 10),
          StartReveal(delay: StartMotion.lineStagger * i, child: line),
        ],
      ],
    );
  }
}
