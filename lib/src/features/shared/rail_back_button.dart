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
