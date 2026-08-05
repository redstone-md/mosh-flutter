// Sessions list screen -- the Flutter port of the React SessionRail sessions
// section (src/features/private-dm/SessionRail.tsx, SessionRailItem). This is
// the slice that makes a DM session reachable from in-app navigation: a
// ListView of one row per SessionSnapshot, a FAB to start a new session, and
// an empty state when no sessions exist.
//
// Scope (this atomic): the combined sessions rail (React SessionRail). DM
// sessions, groups, channels, offers, and orgs are all wired now -- the
// React SessionRail composes them into one rail, and the Flutter side ports
// them surface-by-surface to keep each change small and reviewable.
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
// -> orgs). Channel and group unread counts are wired via
// `unreadChannelCountsProvider` /
// `unreadGroupCountsProvider` (mirrors the DM provider, fingerprint
// comparison; keyed `'channel:<name>'` / `'group:<groupId>'`). Channel/group
// `onTap` stay no-ops (no channel/group screen route).
// Org sections are wired in too (this atomic): each org renders via
// `OrgSection` after the channels loop, separated by a `rail-divider` when
// the prior slices are non-empty. `orgsProvider` (the polled joined-orgs
// list) is watched the same way as channels/groups; the org action helpers
// in `org_actions.dart` (gateway + refresh + navigation) back the 9
// callbacks. `busy` mirrors React's `org.busy = offerBusy || setupBusy` via
// the per-org operation-bus `orgOperationBusProvider` (Set<orgPubkey>): only
// the org being operated on disables, not unrelated orgs.
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
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/features/sessions/org_actions.dart';
import 'package:mosh/src/features/sessions/channel_rail_item.dart';
import 'package:mosh/src/features/sessions/group_rail_item.dart';
import 'package:mosh/src/features/sessions/offer_rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_rail_actions.dart';
import 'package:mosh/src/features/sessions/state_dot.dart';
import 'package:mosh/src/features/sessions/revoked_dm_badges.dart'
    show revokedDmBadgesProvider;
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/dm_offer_providers.dart';
import 'package:mosh/src/state/org_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/shared/avatar.dart';

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
    // Orgs provider -- the React SessionRail section after channels. Watched
    // the same way as channels/groups so an org-roster update re-renders the
    // rail (ADR 0010 server state; mirrors `orgsProvider` 1:1).
    final orgsAsync = ref.watch(orgsProvider);
    // Pending DM offers (channel/group dmOffers flattened) -- the React
    // `useDmOffers pendingOffers`. Derived from channelsAsync + groupsAsync,
    // so it auto-refreshes when either invalidates (a dismiss/join/leave
    // re-polls and the offer row disappears). Rendered at the TOP of the
    // rail (React SessionRail order: offers -> sessions -> groups -> channels).
    final pendingOffers = ref.watch(pendingDmOffersProvider);
    // Unread lifecycle map -- the React `useUnreadNotifications.unread`
    // port (unread_lifecycle_provider.dart). It merges the DM/channel/group
    // count maps into ONE diffed map keyed `dm:<id>` / `channel:<name>` /
    // `group:<id>`, and is the source the rail reads so clearOnActive takes
    // effect (the active conversation's badge clears when focused). The
    // raw count providers (unreadDmCountsProvider etc.) stay the upstream
    // the lifecycle provider watches; the screen no longer reads them
    // directly. Reads the notifier so `clearUnread(key)` is callable on
    // select (mirrors React's rail `onSelect` calling clearUnread).
    final unread = ref.watch(unreadLifecycleProvider);
    final unreadNotifier = ref.read(unreadLifecycleProvider.notifier);
    // The active-conversation key (active_conversation_key_provider.dart),
    // set on select + open + cleared on leave (mirrors React's
    // `activeConversationKey`). Reads the notifier for the set call below.
    final activeKeyNotifier = ref.read(activeConversationKeyProvider.notifier);
    // The active-conversation key VALUE (mirrors React's
    // `activeConversationKey`). Watched so the rail re-renders + marks the
    // open row as selected (React `rail-item-active`,
    // SessionRail.tsx:254-296). The key matches the one the rail sets below
    // (`dm:<id>` / `group:<id>` / `channel:<name>`), so the highlight stays
    // when the chat screen's initState re-sets the same key.
    final String? activeKey = ref.watch(activeConversationKeyProvider);
    // Revoked-org DM badges -- the React `SessionRail` subtitle branch
    // (SessionRail.tsx L36-38): session-id -> org-name for org-bound DMs whose
    // peer left the roster. Degrades to an empty map while orgs load or on
    // error so the badge stays absent during a refresh.
    final revokedBadges = ref.watch(revokedDmBadgesProvider);
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
          final orgs = orgsAsync.value ?? const <OrgSnapshot>[];
          final sessions = snapshot.sessions;
          // Empty only when ALL five slices are empty (offers + sessions +
          // groups + channels + orgs).
          if (pendingOffers.isEmpty &&
              sessions.isEmpty &&
              channels.isEmpty &&
              groups.isEmpty &&
              orgs.isEmpty) {
            return _EmptyState(onStart: () => startChatAction(context, ref));
          }
          // React SessionRail order: sessions, [divider if groups && sessions],
          // groups, [divider if channels && (sessions || groups)], channels.
          // A `Divider` renders only between two non-empty adjacent sections,
          // mirroring React's conditional `rail-divider` rendering.
          final children = <Widget>[
            for (final pending in pendingOffers)
              OfferRailItem(
                pending: pending,
                onAccept: () => acceptOfferAction(context, ref, pending),
                onDismiss: () => dismissOfferAction(ref, pending),
              ),
            if (pendingOffers.isNotEmpty && sessions.isNotEmpty)
              const Divider(height: 1, thickness: 1),
            for (final session in sessions)
              _SessionRow(
                session: session,
                unreadCount: unread['dm:${session.sessionId}'] ?? 0,
                revokedOrgName: revokedBadges[session.sessionId],
                // Highlight the open DM row (React `rail-item-active`,
                // SessionRail.tsx:254-296). Same key the rail sets below.
                active: activeKey == 'dm:${session.sessionId}',
                // Select hook: clear this conversation's badge + mark it the
                // active conversation so the lifecycle clears it on focus
                // (mirrors React's rail `onSelect` -> clearUnread(key) +
                // activeConversationKey set). The navigate still runs after.
                onSelect: () {
                  unreadNotifier.clearUnread('dm:${session.sessionId}');
                  activeKeyNotifier.set('dm:${session.sessionId}');
                },
              ),
            if (groups.isNotEmpty && sessions.isNotEmpty)
              const Divider(height: 1, thickness: 1),
            for (final group in groups)
              // Count comes from `unreadGroupCountsProvider`, keyed
              // `'group:<groupId>'` (fingerprint comparison) -- mirrors the
              // DM row's `unread['dm:<sessionId>']` lookup.
              GroupRailItem(
                group: group,
                unreadCount: unread['group:${group.groupId}'] ?? 0,
                // Highlight the open group row (React `rail-item-active`,
                // SessionRail.tsx:254-296). Same key the rail sets below.
                active: activeKey == 'group:${group.groupId}',
                // Select hook: same clearUnread + activeKey set as the DM
                // row, keyed `'group:<groupId>'` (the group identity).
                onSelect: () {
                  unreadNotifier.clearUnread('group:${group.groupId}');
                  activeKeyNotifier.set('group:${group.groupId}');
                },
              ),
            if (channels.isNotEmpty &&
                (sessions.isNotEmpty || groups.isNotEmpty))
              const Divider(height: 1, thickness: 1),
            for (final channel in channels)
              // Count comes from `unreadChannelCountsProvider`, keyed
              // `'channel:<name>'` (fingerprint comparison).
              ChannelRailItem(
                channel: channel,
                unreadCount: unread['channel:${channel.name}'] ?? 0,
                // Highlight the open channel row (React `rail-item-active`,
                // SessionRail.tsx:254-296). Same key the rail sets below.
                active: activeKey == 'channel:${channel.name}',
                // Select hook: same clearUnread + activeKey set as the DM
                // row, keyed `'channel:<name>'`.
                onSelect: () {
                  unreadNotifier.clearUnread('channel:${channel.name}');
                  activeKeyNotifier.set('channel:${channel.name}');
                },
              ),
            for (final org in orgs) ...[
              // React SessionRail renders each org wrapped in a
              // `rail-divider` + `OrgSection` (the divider is INSIDE the
              // per-org map, unconditional, so N orgs render N dividers --
              // one above each org header). The 7 callbacks pass through to
              // the org action helpers (gateway + refresh + navigation);
              // `busy` mirrors React's `org.busy = offerBusy || setupBusy`
              // via the per-org operation-bus (only this org disables while
              // its leave/offer/member/new-group action is in flight).
              const Divider(height: 1, thickness: 1),
              OrgSection(
                org: org,
                busy:
                    ref.watch(orgOperationBusProvider).contains(org.orgPubkey),
                onMember: (o, m) => openMemberDmAction(context, ref, o, m),
                onAcceptDmOffer: (pubkey, id) =>
                    acceptOrgDmOfferAction(context, ref, pubkey, id),
                onDismissDmOffer: (pubkey, id) =>
                    dismissOrgDmOfferAction(context, ref, pubkey, id),
                onAcceptGroupOffer: (pubkey, id) =>
                    acceptOrgGroupOfferAction(context, ref, pubkey, id),
                onDismissGroupOffer: (pubkey, id) =>
                    dismissOrgGroupOfferAction(context, ref, pubkey, id),
                onCreateGroup: (o, label) =>
                    createOrgGroupAction(context, ref, o, label),
                onLeave: (o) => leaveOrgAction(context, ref, o),
                l: l,
              ),
            ],
          ];
          return RefreshIndicator(
            onRefresh: () => ref.read(sessionListProvider.notifier).refresh(),
            child: ListView(children: children),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.shellNewSession),
        onPressed: () => startChatAction(context, ref),
      ),
    );
  }
}

/// One DM session row. Mirrors the React `SessionRailItem`:
///   - leading: Avatar (CircleAvatar with the label's initials via
///     [avatarInitials] -- React's split-on-whitespace/underscore/dash +
///     first-char-of-each + take-2 + uppercase algorithm; the background
///     color is a stable hash of the LABEL (React `<Avatar name={label} />`
///     hashes the name), so two sessions with the same peer get the same
///     color -- matching React's per-`name` Avatar styling).
///   - title: the label, falling back peer -> own display -> raw session id
///     (the same chain `dm_screen` uses for its title).
///   - subtitle: the localized state label (`stateIdle|stateWaiting|stateReady`
///     or the raw state string for unknown states).
///     OR -- when this DM's linked peer is no longer in the org roster -- the
///     React `SessionRail` revoked branch (SessionRail.tsx L36-38):
///     `${orgText.revokedBadge} ${revokedOrgName}` (the "no longer in `<org>`"
///     badge). The
///     revoked-org name is looked up from `revokedDmBadgesProvider` at the
///     call site (DM rows only).
///   - trailing: a colored state dot plus an `UnreadBadge` (count > 0)
///     mirroring React's `SessionRailItem` trailing slot.
///   - onTap: navigate to the DM screen for this session id.
///   - Semantics mirrors React's `aria-label="Open session with ${label}"`.
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    this.active = false,
    this.unreadCount = 0,
    this.revokedOrgName,
    this.onSelect,
  });

  final SessionSnapshot session;
  // Highlight the open DM row (React `rail-item-active`,
  // SessionRail.tsx:254-296). Passed to `ListTile(selected:)` -- the
  // idiomatic selected-tile highlight (theme `selectedTileColor`).
  final bool active;
  final int unreadCount;
  final String? revokedOrgName;

  /// Optional select hook called BEFORE the navigate, so the parent
  /// (SessionsScreen) can clear the unread badge + set the active
  /// conversation key for this session (mirrors React's rail `onSelect`
  /// calling `clearUnread(conversationKey(item))`). Null keeps the prior
  /// navigate-only behavior.
  final VoidCallback? onSelect;

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
    // React `<Avatar name={label} />` hashes the LABEL (peer display name),
    // not the session id -- so two sessions with the same peer get the same
    // color. Hashing sessionId here would diverge (same peer, different colors).
    final bg = avatarColor(label);
    return Semantics(
      label: 'Open session with $label',
      button: true,
      selected: active,
      child: ListTile(
        leading: Avatar(
          name: label,
          radius: 20,
          foregroundColor:
              ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          revokedOrgName != null
              ? '${l.orgRevokedBadge} $revokedOrgName'
              : stateText,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StateDot(state: session.state),
            const SizedBox(width: 8),
            UnreadBadge(count: unreadCount),
          ],
        ),
        // `selected: active` is the Flutter `rail-item-active` equivalent
        // (theme selected tile color), matching GroupRailItem/ChannelRailItem.
        selected: active,
        onTap: () {
          // Select hook first (clear badge + set active key), then navigate
          // -- mirrors React's rail `onSelect` -> clearUnread(key) then the
          // screen swaps. The navigate stays identical for behavior parity.
          onSelect?.call();
          context.go(AppRoutes.dmFor(session.sessionId));
        },
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
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
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
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
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
