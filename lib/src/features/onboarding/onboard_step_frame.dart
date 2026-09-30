// Shared onboarding step-frame: a Back button at the top (arrow-back
// icon + the localized "Back" label), then the step title (the theme's
// headlineSmall), then the step body (the `child`).
//
// Two widgets live here:
//  - `OnboardStepFrame`: full-screen route wrapper -- Scaffold + SafeArea +
//    Center + scroll + 32px padding + 460px column around the body, used
//    by the chat / group / join / channel step screens pushed as routes.
//  - `OnboardStepBody`: just the Column, exposed so the desktop chat-pane
//    can compose a step INLINE. It adds no scroll, padding or width cap of
//    its own: ChatPaneWelcome already supplies them, so an inline step sits
//    exactly where the menu it replaced did.
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
