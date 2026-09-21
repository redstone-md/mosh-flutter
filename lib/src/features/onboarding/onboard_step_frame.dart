// Shared onboarding step-frame: a Back button at the top (arrow-back
// icon + the localized "Back" label), then the step title
// (headlineSmall), then the step body (the `child`).
//
// Two widgets live here:
//  - `OnboardStepFrame`: full-screen route wrapper -- Scaffold + SafeArea +
//    Center + the body, used by the chat / group / join / channel step
//    screens pushed as full routes.
//  - `OnboardStepBody`: the Scaffold-free body (SingleChildScrollView +
//    ConstrainedBox + Column), exposed so the desktop chat-pane can compose
//    a step INLINE (inside its own scroll container) instead of pushing a
//    full-screen route.
//
// The frame is intentionally presentation-only: it owns no state and calls
// back through `onBack` -- the parent owns the busy / copied / lastInvite
// state and the routing decisions.
library;

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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(
                  l.onboardBack,
                  style: const TextStyle(fontSize: 12, color: MoshColors.fg3),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: MoshColors.fg3,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                letterSpacing: -0.19,
                color: MoshColors.fg1,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Reusable step frame for the NewSessionPanel step screens.
///
/// Full-screen route wrapper: [Scaffold] + [SafeArea] + [Center] around
/// [OnboardStepBody]. State stays in the caller.
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
          child: OnboardStepBody(title: title, onBack: onBack, child: child),
        ),
      ),
    );
  }
}
