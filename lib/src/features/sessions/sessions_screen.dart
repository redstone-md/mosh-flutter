import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/conversation_action_error.dart'
    show ConversationActionError;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/sessions/sessions_rail_list.dart';
import 'package:mosh/src/features/sessions/sessions_list_controls.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_rail_actions.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider, sessionsOf;

/// The DM sessions-list screen: one row per conversation, a FAB to start a
/// new session, and an empty state. See the file header for how the rail is
/// composed.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  String _query = '';
  ConversationKind? _kind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(conversationListProvider(ConversationKind.dm));

    // The rail carries NO header of
    // its own; the shell titlebar sits above it.
    return Scaffold(
      backgroundColor: MoshColors.bg0,
      // The rail carries no AppBar, so nothing else keeps it clear of the
      // status bar / camera cutout. Desktop gets that clearance from the
      // shell titlebar above it; the mobile shell is a bare IndexedStack, so
      // on Android 15+ (edge-to-edge is mandatory there) the first row drew
      // under the cutout. Inside the Scaffold, so bg0 still paints edge to
      // edge behind the status bar and only the content is inset.
      body: SafeArea(
        child: Padding(
          // Pinned controls inset themselves; the list insets its rows
          // inside the scroller, so its scrollbar runs in the right gutter
          // and both sides of a row stay [kRailPadding] from the edge.
          padding: const EdgeInsets.symmetric(vertical: kRailPadding),
          child: Column(
            children: <Widget>[
              // The NewSession button + its divider are pinned above
              // `.rail-list`, outside the scroller and independent of whether
              // any conversation exists.
              _inset(RailNewButton(
                label: l.shellNewSession,
                onTap: () => openNewSessionAction(context, ref),
              )),
              const SizedBox(height: kRailPadding),
              _inset(SessionsListControls(
                focusNode: ref.watch(chatListSearchFocusProvider),
                kind: _kind,
                onSearch: (value) => setState(() => _query = value),
                onKind: (value) => setState(() => _kind = value),
              )),
              SizedBox(height: isMobileBreakpoint(context) ? 4 : 8),
              Expanded(
                child: SessionsRailList(
                  dmSessions: sessionsOf(async.value),
                  query: _query,
                  kind: _kind,
                  status: async.when<Widget?>(
                    loading: () => SizedBox(
                      height: kRailItemHeight,
                      child: Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: l.sessionsLoading,
                        ),
                      ),
                    ),
                    error: (e, _) => _ErrorState(error: e, ref: ref),
                    data: (_) => null,
                  ),
                ),
              ),
              // The gear, pinned BELOW the scroller (the same fixed slot
              // the NewSession button holds above it) so it never scrolls
              // away — the Discord placement.
              const SizedBox(height: kRailPadding),
              _inset(RailSettingsButton(
                label: l.settingsGearLabel,
                onTap: () => context.push(AppRoutes.settings),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: kRailPadding),
      child: child);
}

/// Error state with a Retry button that re-runs the DM entry's refresh.
/// Shares the rail's scroll area so Retry stays reachable in short windows.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.ref});

  final Object error;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Only a bridge failure has a worded reason. Anything else would show
    // raw exception text, so the title and Try again stand alone.
    final reason = ConversationActionError.of(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // One live region, so a screen reader announces the failure
            // and its reason together when the list fails to load.
            Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                children: [
                  Text(
                    l.sessionsError,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (reason.kind != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      reason.describe(l),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => ref
                  .read(
                    conversationListProvider(ConversationKind.dm).notifier,
                  )
                  .refresh(),
              child: Text(l.sessionsRetry),
            ),
          ],
        ),
      ),
    );
  }
}
