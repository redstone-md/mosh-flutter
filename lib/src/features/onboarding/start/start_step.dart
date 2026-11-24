import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/settings/settings_card.dart';

/// The Start menu step of the Wizard step card: a step opened from the start
/// menu has no count, only the way back. Its heading is the question, the
/// line under it says what the step does, and [child] answers it on a card.
class StartStep extends StatelessWidget {
  const StartStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.child,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget child;

  /// Width of a step's column on the desktop.
  static const maxWidth = 480.0;

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
                icon: const Icon(MoshIcons.back),
                label: Text(l.onboardBack),
              ),
            ),
            const SizedBox(height: MoshSpace.s5),
            Semantics(
              header: true,
              child: Text(title,
                  textAlign: TextAlign.center, style: text.headlineMedium),
            ),
            const SizedBox(height: MoshSpace.s2),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: text.bodyLarge!
                    .copyWith(color: MoshColors.of(context).onSurfaceVariant)),
            const SizedBox(height: MoshSpace.s5),
            SettingsSurface(child: child),
          ],
        ),
      ),
    );
  }
}
