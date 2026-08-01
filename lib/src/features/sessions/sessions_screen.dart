// Sessions list screen -- the Flutter port of the React SessionRail sessions
// section (src/features/private-dm/SessionRail.tsx, SessionRailItem). This is
// the slice that makes a DM session reachable from in-app navigation: a
// ListView of one row per SessionSnapshot, a FAB to start a new session, and
// an empty state when no sessions exist.
//
// Scope (this atomic): the DM sessions list ONLY. Channels, groups, offers,
// orgs, search, and filter are deferred to later atomics -- the React
// SessionRail composes all of them into one rail, but the Flutter side is
// being ported surface-by-surface to keep each change small and reviewable.
// The unread badge is wired for DM sessions via `unreadDmCountsProvider`
// (counts not-own messages per session, keyed `'dm:<sessionId>'`, mirroring
// React's `useUnreadNotifications`). The full poll-diff lifecycle
// (notifications, window-focus, clearOnActive, `diffConversations`,
// `lastSeen` persistence) is a later atomic -- here the count shown is the
// number of not-own messages currently in the session.
//
// Channel/group rail items are now wired in too (this atomic): the screen
// lays out DM sessions, then groups, then channels, with thin `rail-divider`
// lines between two non-empty adjacent sections -- 1-в-1 with the React
// `SessionRail` combined rail order (offers -> sessions -> groups -> channels
// -> orgs; offers/orgs remain deferred, no providers/widgets yet). Channel
// and group unread counts are passed as 0 for now: no channel/group unread
// provider exists yet, so computing them from the snapshots is a later
// atomic. Channel/group `onTap` stay no-ops (no channel/group screen route).
//
// State split (ADR 0010): server state lives in `sessionListProvider`
// (AsyncNotifierProvider<SessionListSnapshot>) -- the TanStack-Query
// analogue; loading/data/error flows through AsyncValue. The new-session
// flow reuses the cross-screen `inviteFlowProvider` Notifier (the same one
// onboarding uses) so display-name + listen-port stay DRY and consistent.
// No widget-local state is needed beyond obtaining the ScaffoldMessenger
// inside the tap callback (not stored on the widget), so a ConsumerWidget
// would suffice -- but ConsumerStatefulWidget mirrors the other slice-one
// screens and leaves room for a selection animation in a later atomic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/features/sessions/channel_rail_item.dart';
import 'package:mosh/src/features/sessions/group_rail_item.dart';
import 'package:mosh/src/features/sessions/state_dot.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/unread_providers.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';

/// The DM sessions-list screen. 1-в-1 with the React SessionRail sessions
/// section: one row per `SessionSnapshot`, a FAB to start a new session,
/// and an empty state. See the file header for the deferred-scope note.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

 @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(sessionListProvider);
    // Channels/groups providers -- the React SessionRail sections after DMs.
    // Watched here so a channel/group list update re-renders the combined rail
    // (ADR 0010 server state, mirrors `sessionListProvider` 1:1).
    final channelsAsync = ref.watch(channelListProvider);
    final groupsAsync = ref.watch(groupListProvider);
    // Unread map is data-only; AsyncValue guards leave it {} while loading
    // or on error so the badge simply stays absent (mirrors React clearing
    // to 0 visually during a refresh).
    final unread = ref.watch(unreadDmCountsProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: Text(l.sessionsListTitle),
        actions: [
          IconButton(
            // Match the onboarding AppBar action (cable_outlined -> /diagnostics).
            icon: const Icon(Icons.cable_outlined),
            tooltip: l.diagnosticsDiagnostics,
            onPressed: () => context.go(AppRoutes.diagnostics),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(error: e, ref: ref),
        data: (snapshot) {
          // Channels/groups augment the DM list (React's combined SessionRail).
          // They resolve independently via their own providers; while loading
          // or on error they degrade to an empty list (`.value` returns the
          // nullable snapshot, so `.value?.X ?? const []` contributes nothing)
          // so the DM rows still render -- the sessions screen is primarily
          // DMs and channels/groups are additive. Channels/groups auto-refresh
          // on their own provider invalidation, so the RefreshIndicator only
          // refreshes the DM list (kept minimal).
          final channels = channelsAsync.value?.channels ?? const [];
          final groups = groupsAsync.value?.groups ?? const [];
          final sessions = snapshot.sessions;
          // Empty only when ALL three slices are empty (offers/orgs deferred).
          if (sessions.isEmpty && channels.isEmpty && groups.isEmpty) {
            return _EmptyState(onStart: () => _startChat(context, ref));
          }
          // React SessionRail order: sessions, [divider if groups && sessions],
          // groups, [divider if channels && (sessions || groups)], channels.
          // A `Divider` renders only between two non-empty adjacent sections,
          // mirroring React's conditional `rail-divider` rendering.
          final children = <Widget>[
            for (final session in sessions)
              _SessionRow(
                session: session,
                unreadCount: unread['dm:${session.sessionId}'] ?? 0,
              ),
            if (groups.isNotEmpty && sessions.isNotEmpty)
              const Divider(height: 1, thickness: 1),
            for (final group in groups)
              // TODO(channel-group-unread): channel/group unread counts are a
              // later atomic (no channel/group unread provider yet); pass 0.
              GroupRailItem(group: group, unreadCount: 0),
            if (channels.isNotEmpty &&
                (sessions.isNotEmpty || groups.isNotEmpty))
              const Divider(height: 1, thickness: 1),
            for (final channel in channels)
              // TODO(channel-group-unread): see the groups loop above.
              ChannelRailItem(channel: channel, unreadCount: 0),
          ];
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(sessionListProvider.notifier).refresh(),
            child: ListView(children: children),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.shellNewSession),
        onPressed: () => _startChat(context, ref),
      ),
    );
  }

  // Mirrors onboarding's _startChat: inviteFlowProvider.create() then surfaces
  // the invite URI as a SnackBar. ScaffoldMessenger is captured at call time
  // (not stored) to avoid holding a context across an await.
  Future<void> _startChat(BuildContext context, WidgetRef ref) async {
    final scaffold = ScaffoldMessenger.of(context);
    final invite = await ref.read(inviteFlowProvider.notifier).create();
    scaffold.showSnackBar(SnackBar(content: Text(invite.inviteUri)));
  }
}

/// One DM session row. Mirrors the React `SessionRailItem`:
///   - leading: Avatar (CircleAvatar with the label's first letter; the
///     background color is a stable hash of the session id so different
///     sessions get distinct avatar colors, matching React's per-`name` Avatar
///     styling).
///   - title: the label, falling back peer -> own display -> raw session id
///     (the same chain `dm_screen` uses for its title).
///   - subtitle: the localized state label (`stateIdle|stateWaiting|stateReady`
///     or the raw state string for unknown states).
///   - trailing: a colored state dot plus an `UnreadBadge` (count > 0)
///     mirroring React's `SessionRailItem` trailing slot.
///   - onTap: navigate to the DM screen for this session id.
///   - Semantics mirrors React's `aria-label="Open session with ${label}"`.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, this.unreadCount = 0});

  final SessionSnapshot session;
  final int unreadCount;

  String _label() {
    if (session.peerDisplayName.isNotEmpty) return session.peerDisplayName;
    if (session.displayName.isNotEmpty) return session.displayName;
    return session.sessionId;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final label = _label();
    final stateText = stateLabel(l, session.state);
    final bg = avatarColor(session.sessionId);
    return Semantics(
      label: 'Open session with $label',
      button: true,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: bg,
          foregroundColor:
              ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
          child: Text(
            label.isEmpty ? '?' : label[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(stateText),
       trailing: Row(
         mainAxisSize: MainAxisSize.min,
        children: [
          StateDot(state: session.state),
          const SizedBox(width: 8),
          UnreadBadge(count: unreadCount),
        ],
       ),
        onTap: () => context.go(AppRoutes.dmFor(session.sessionId)),
      ),
    );
  }
}

/// Empty state for the sessions list. Reuses the same ARB keys as the React
/// `chatNoSessionTitle` + `chatNoSessionBody` welcome, with the
/// `chatStartCta` ("New private chat") button mirroring onboarding's Chat
/// tile -- both call the same `inviteFlowProvider.create()` flow.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.chatNoSessionTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.chatNoSessionBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add),
              label: Text(l.chatStartCta),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state with a Retry button that re-runs `sessionListProvider.refresh()`.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.ref});

  final Object error;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.sessionsError,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => ref.read(sessionListProvider.notifier).refresh(),
              child: Text(l.sessionsRetry),
            ),
          ],
        ),
      ),
    );
  }
}
