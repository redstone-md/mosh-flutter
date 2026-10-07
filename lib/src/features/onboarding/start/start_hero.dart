import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'start_motion.dart';
import 'start_reveal.dart';

/// The start menu's welcome: a greeting, the title, what Mosh protects
/// and, when [illustrated], the hero illustration beside them.
class StartHero extends StatelessWidget {
  const StartHero({super.key, required this.illustrated});

  final bool illustrated;

  @override
  Widget build(BuildContext context) {
    final copy = _HeroCopy(l: AppLocalizations.of(context)!);
    if (!illustrated) return copy;
    return Row(children: [
      Expanded(flex: 5, child: copy),
      const SizedBox(width: 24),
      Expanded(
        flex: 6,
        child: StartReveal(
          delay: StartMotion.lineStagger * 3,
          child: ExcludeSemantics(
            child: Image.asset(
              'assets/start/hero.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final lines = <Widget>[
      Text(
        l.startEyebrow,
        style: text.bodyMedium?.copyWith(color: MoshColors.fg3),
      ),
      Semantics(
        header: true,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${l.startTitleLead} '),
            TextSpan(
              text: l.startTitleAccent,
              style: const TextStyle(color: MoshColors.moss),
            ),
          ]),
          style: text.displaySmall?.copyWith(
              fontSize: compact ? 34 : 48,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5),
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Text(
          l.startSubtitle,
          style: text.bodyLarge?.copyWith(color: MoshColors.fg2, height: 1.5),
        ),
      ),
    ];
    const gaps = [10.0, 16.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) SizedBox(height: gaps[i - 1]),
          StartReveal(delay: StartMotion.lineStagger * i, child: line),
        ],
      ],
    );
  }
}
