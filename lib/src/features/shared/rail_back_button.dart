// Mobile-only "back to the rail" control for the chat branch.
//
// The shell puts the rail (branch A) and the chat (branch B) in a
// StatefulShellRoute. On desktop both panes are mounted side by side, so a
// back control would be meaningless. On mobile only the ACTIVE branch
// renders, and because each branch owns its own Navigator, branch B's route
// stack is one deep -- `Navigator.canPop` is false, so `AppBar` implies no
// leading arrow of its own. The result was a dead end: once branch B was
// active, nothing on screen returned to the conversation list.
//
// React's mobile shell solves the same problem with the `.titlebar-nav`
// hamburger that reopens the rail as a drawer. The Flutter shell mounts no
// titlebar on mobile, so the affordance lives on each chat pane's own
// AppBar instead.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;

/// The chat panes' AppBar `leading` on mobile; null on desktop (where the
/// rail is already on screen and the slot stays empty).
///
/// Navigating rather than popping is deliberate: it is the same
/// `context.go(AppRoutes.sessions)` the chat screens already use on leave,
/// and it activates branch A instead of unwinding branch B. The active
/// conversation key is left alone, so the rail highlights the row the user
/// just came from.
Widget? railBackButton(BuildContext context) {
  if (!isMobileBreakpoint(context)) return null;
  final l = AppLocalizations.of(context)!;
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    tooltip: l.backToConversations,
    onPressed: () => context.go(AppRoutes.sessions),
  );
}
