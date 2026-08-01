// Shared onboarding step-frame, 1-в-1 with the React `OnboardStepFrame`
// (src/features/private-dm/NewSessionPanel.parts.tsx): a Back button at the
// top (arrow-back icon + the localized "Back" label), then an h1-equivalent
// title (headlineSmall), then the step body (the `child`).
//
// Extracted as its own widget so the chat / group / join / channel step
// screens all reuse the same frame. Only the chat-create step is wired in
// this atomic; the group / join / channel steps are deferred and will
// compose this same frame when they land (DRY: one frame, many steps).
//
// The frame is intentionally presentation-only: it owns no state and calls
// back through `onBack` -- the parent owns the busy / copied / lastInvite
// state and the routing decisions. Keeping it stateless matches the React
// component (a pure render with `title` + `onBack` + `children`).
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

/// Reusable step frame for the NewSessionPanel step screens.
///
/// Renders the React `OnboardStepFrame` layout: a leading Back affordance
/// (`Icons.arrow_back` + the `onboardBack` label), the step title as a
/// headline, then [child] as the step body. State stays in the caller.
class OnboardStepFrame extends StatelessWidget {
  const OnboardStepFrame({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
  });

  /// Step title (1-в-1 with React's `title` prop -> h1.step-title).
  final String title;

  /// Back-navigation callback (1-в-1 with React's `onBack`).
  final VoidCallback onBack;

  /// Step body. The caller composes the body paragraph + buttons + result
  /// (e.g. the chat step renders the body text, the Create button, and
  /// `InviteResult`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                      label: Text(l.onboardBack),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
