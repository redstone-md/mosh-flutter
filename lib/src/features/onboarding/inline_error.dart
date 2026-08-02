// Persistent inline error for the onboarding step screens (1-в-1 with the
// React `<div className="inline-error" role="alert">{props.error}</div>`
// rendered by NewSessionPanel when a create/join handler throws -- see
// NewSessionPanel.tsx:98-101 + private-dm-screen.onboarding.test.tsx:106,119).
//
// React's parent (private-dm-screen) wraps the create/join handlers in
// try/catch and feeds the caught error down as a prop; the error stays
// until the next attempt. Each onboarding step screen mirrors that by
// capturing `error.toString()` into a widget-local `String? _error`,
// clearing it at the START of the next attempt, and rendering it via this
// widget BELOW the primary button. This is one source of truth -- the
// transient SnackBar the screens used before auto-dismissed and was not
// announced to assistive tech (no role="alert" equivalent).
//
// `Semantics(liveRegion: true, container: true)` is the Flutter equivalent
// of `role="alert"` (a polite live region): the same pattern invite_paste's
// `_DetectBadge` and diagnostics `RuntimeError` already use in this repo.
// No new ARB strings -- React stringifies the raw error (`{props.error}`);
// this widget renders the same string verbatim.
library;

import 'package:flutter/material.dart';

/// Persistent inline error displayed below the primary button on the
/// onboarding step screens when a create/join handler fails.
///
/// Renders only when [message] is non-null (mirrors React's
/// `props.error ? (...) : null`). When null it returns
/// `const SizedBox.shrink()` so the layout below the button does not jump.
/// The error-colored `Text` is wrapped in `Semantics(liveRegion: true,
/// container: true, label: message)` so screen readers announce it when it
/// appears, matching React's `role="alert"`.
class InlineError extends StatelessWidget {
  const InlineError({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      child: Text(
        text,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    );
  }
}
