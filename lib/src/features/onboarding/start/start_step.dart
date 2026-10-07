import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// A start menu step: Back, the step's illustration, its title and what it
/// does, then [child] on a raised card.
class StartStep extends StatelessWidget {
  const StartStep({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.child,
  });

  /// Asset path of the step illustration.
  final String image;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget child;

  static const maxWidth = 640.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(l.onboardBack),
                style: TextButton.styleFrom(foregroundColor: MoshColors.fg2),
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Image.asset(image, height: 148, fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: text.bodyMedium
                    ?.copyWith(color: MoshColors.fg2, height: 1.55)),
            const SizedBox(height: 24),
            DecoratedBox(
              decoration: BoxDecoration(
                color: MoshColors.bg1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MoshColors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
