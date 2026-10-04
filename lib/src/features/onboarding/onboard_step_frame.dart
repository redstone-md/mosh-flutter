import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';

/// Scaffold-free step body shared by the onboarding step screens.
///
/// Renders the step body layout: a leading Back affordance
/// (`Icons.arrow_back` + the `onboardBack` label), the step title as a
/// headline, then [child] as the step body. State stays in the caller.
///
/// Use this directly when composing a step INLINE (e.g. inside the desktop
/// chat-pane's own scroll container). Use [OnboardStepFrame] when the step
/// is pushed as a full-screen route.
class OnboardStepBody extends StatelessWidget {
  const OnboardStepBody({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
  });

  /// Step title.
  final String title;

  /// Back-navigation callback.
  final VoidCallback onBack;

  /// Step body. The caller composes the body paragraph + buttons + result
  /// (e.g. the chat step renders the body text, the Create button, and
  /// `InviteResult`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(
              l.onboardBack,
              style: text.bodySmall?.copyWith(color: MoshColors.fg3),
            ),
            style: TextButton.styleFrom(
              foregroundColor: MoshColors.fg3,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: text.headlineSmall),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

/// Reusable step frame for the NewSessionPanel step screens.
///
/// Full-screen route wrapper: [Scaffold] + [SafeArea] + [Center] + a
/// padded, width-capped scroll around [OnboardStepBody]. State stays in
/// the caller.
class OnboardStepFrame extends StatelessWidget {
  const OnboardStepFrame({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
  });

  /// Step title.
  final String title;

  /// Back-navigation callback.
  final VoidCallback onBack;

  /// Step body. The caller composes the body paragraph + buttons + result
  /// (e.g. the chat step renders the body text, the Create button, and
  /// `InviteResult`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: OnboardStepBody(
                title: title,
                onBack: onBack,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
