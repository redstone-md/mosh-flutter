// Sessions list screen. One row per conversation, a FAB to start a new
// session, and an empty state. The combined rail order is
// offers -> sessions -> groups -> channels -> orgs, separated by
// `rail-divider` lines between two non-empty adjacent sections.
//
// The rail builds ONE list of [RailEntry] values per paint -- one entry per
// conversation, whatever kind it is -- and loops over it once. Each entry
// names the conversation it opens ([RailEntry.ref]) and renders its own row
// through the shared rail-row widget, so the three things that used to be
// written once per kind (the unread lookup, the active highlight and the
// clear-on-tap) are written once, from the entry's key. A new kind adds one
// [RailEntry] subclass and one section below; the loop does not change.
// Unread counts come from `unreadLifecycleProvider`, which merges the
// per-kind counts into ONE diffed map keyed by [ConversationRef.key].
// Orgs render after the channels; `org_actions.dart` backs the 7 callbacks,
// each reduced to its own bridge-facade call and its own destination -- the busy
// flag, the refresh, the error toast and the navigation belong to the one
// envelope they all run in. `busy` comes from `orgOperationBusProvider`
// (Set<orgPubkey>).
//
// State split (ADR 0010): server state lives in the
// `conversationListProvider` family (one entry per conversation kind) --
// loading/data/error flows through AsyncValue.
// The DM entry drives the rail's loading and error states; a channel or a
// group entry degrades to no rows, so one slow slice never blanks the rail.
// The new-session flow reuses the cross-screen `inviteFlowProvider` Notifier
// so display-name + listen-port stay DRY. No widget-local state, so a
// ConsumerWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/features/sessions/org_actions.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_rail_actions.dart';
import 'package:mosh/src/features/sessions/revoked_dm_badges.dart'
    show revokedDmBadgesProvider;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/state/conversation_providers.dart'
    show channelsOf, conversationListProvider, groupsOf, sessionsOf;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/state/dm_offer_providers.dart';
import 'package:mosh/src/state/org_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The DM sessions-list screen: one row per conversation, a FAB to start a
/// new session, and an empty state. See the file header for how the rail is
/// composed.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    // The DM entry drives the rail's loading/error states; the other
    // kinds degrade to no rows inside [_RailList].
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
          padding: const EdgeInsets.all(kRailPadding),
          child: Column(
            children: <Widget>[
              // The NewSession button + its divider are pinned above
              // `.rail-list`, outside the scroller and independent of whether
              // any conversation exists.
              RailNewButton(
                label: l.shellNewSession,
                onTap: () => openNewSessionAction(context, ref),
              ),
              const SizedBox(height: kRailPadding),
              const RailDivider(),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorState(error: e, ref: ref),
                  data: (list) => _RailList(dmSessions: sessionsOf(list)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The data-state rail: offers -> sessions -> groups -> channels -> orgs,
/// flattened from per-kind [RailEntry] slices with a [RailDivider] between
/// two non-empty adjacent sections. Owns the per-row chrome (unread count,
/// active highlight, clear-on-select) built from the entry's own
/// [RailEntry.ref].
class _RailList extends ConsumerWidget {
  const _RailList({required this.dmSessions});

  /// The DM slice; channels/groups/orgs are read from their own providers
  /// (loading or error degrades to no rows, so the DM rows still render).
  final List<SessionSnapshot> dmSessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    // Channels/groups augment the DM list. They are their own entries in the
    // conversation-list family; loading or error degrades to
    // no rows, so the DM rows still render.
    final channels = channelsOf(ref
        .watch(
          conversationListProvider(ConversationKind.channel),
        )
        .value);
    final groups = groupsOf(ref
        .watch(
          conversationListProvider(ConversationKind.group),
        )
        .value);
    // Orgs provider, watched so an org-roster update re-renders the
    // rail (ADR 0010 server state).
    final orgs = ref.watch(orgsProvider).value ?? const <OrgSnapshot>[];
    // Pending DM offers (channel/group dmOffers flattened). Derived from
    // the channel/group lists, so it auto-refreshes when either
    // invalidates (a dismiss/join/leave re-polls and the offer row
    // disappears). Rendered at the TOP of the rail.
    final pendingOffers = ref.watch(pendingDmOffersProvider);
    // Unread lifecycle map: merges the per-kind counts into ONE diffed map
    // keyed by `ConversationRef.key`, so clearOnActive takes effect. Reads
    // the notifier so `clearUnread(key)` is callable on select.
    final unread = ref.watch(unreadLifecycleProvider);
    final unreadNotifier = ref.read(unreadLifecycleProvider.notifier);
    // The active-conversation key (active_conversation_key_provider.dart),
    // set on select + open + cleared on leave. Reads the notifier for the
    // set call below.
    final activeKeyNotifier = ref.read(activeConversationKeyProvider.notifier);
    // The active-conversation key VALUE. Watched so the rail re-renders +
    // marks the open row as selected. The key is the one the rail sets
    // below, so the highlight stays when the chat screen's initState
    // re-sets it.
    final String? activeKey = ref.watch(activeConversationKeyProvider);
    // Revoked-org DM badges:
    // session-id -> org-name for org-bound DMs whose
    // peer left the roster. Degrades to an empty map while orgs load or on
    // error so the badge stays absent during a refresh.
    final revokedBadges = ref.watch(revokedDmBadgesProvider);

    // What the rail hands each row: its unread count, whether it is the open
    // conversation, and the hook that clears the badge + marks it open. All
    // three come from the row's own [RailEntry.ref], so the `kind:id` key is
    // written here and nowhere else in the screen.
    RailRowChrome chromeFor(RailEntry entry) {
      final conversation = entry.ref;
      // A row with no conversation behind it (a pending offer) has no badge
      // to clear and no conversation to mark open.
      if (conversation == null) {
        return (unreadCount: 0, active: false, onSelect: null);
      }
      final key = conversation.key;
      return (
        unreadCount: unread[key] ?? 0,
        active: key == activeKey,
        onSelect: () {
          unreadNotifier.clearUnread(key);
          activeKeyNotifier.set(key);
        },
      );
    }

    // One entry per conversation, in rail order:
    // offers -> sessions -> groups -> channels. A section is
    // one kind's slice; the loop below flattens them.
    final sections = <List<RailEntry>>[
      [
        for (final offer in pendingOffers)
          OfferRailEntry(
            pending: offer,
            onAccept: () => acceptOfferAction(context, ref, offer),
            onDismiss: () => dismissOfferAction(ref, offer),
          ),
      ],
      [
        for (final session in dmSessions)
          DmRailEntry(
            session,
            revokedOrgName: revokedBadges[session.sessionId],
          ),
      ],
      [for (final group in groups) GroupRailEntry(group)],
      [for (final channel in channels) ChannelRailEntry(channel)],
    ];
    // Empty only when no section has a row and there is no org either.
    if (!sections.any((section) => section.isNotEmpty) && orgs.isEmpty) {
      return _EmptyState(
        onStart: () => openNewSessionAction(context, ref),
      );
    }
    // One pass builds the rail: a [RailDivider] between two non-empty
    // adjacent sections (the header contract above; the pre-08 loop had
    // pair-specific divider conditions, so offers+groups or
    // offers+channels with no sessions between them now also get one),
    // then one row per conversation.
    final children = <Widget>[];
    for (final section in sections) {
      if (section.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const RailDivider());
      }
      for (final entry in section) {
        children.add(entry.buildRow(context, chromeFor(entry)));
      }
    }
    // Each org renders wrapped in a `rail-divider` + [OrgSection] (the
    // divider is INSIDE the per-org loop, unconditional, so N orgs render
    // N dividers -- one above each org header). The 7 callbacks pass
    // through to the org action helpers (gateway + refresh + navigation);
    // `busy` comes from the per-org operation-bus (only this org disables
    // while its leave/offer/member/new-group action is in flight).
    final orgBusy = ref.watch(orgOperationBusProvider);
    for (final org in orgs) {
      children.add(const RailDivider());
      children.add(
        OrgSection(
          org: org,
          busy: orgBusy.contains(org.orgPubkey),
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
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh(),
      child: ListView(children: children),
    );
  }
}

/// Empty state for the sessions list. Reuses the
/// `chatNoSessionTitle` + `chatNoSessionBody` welcome, with the
/// `chatStartCta` ("New private chat") button mirroring onboarding's Chat
/// tile -- both open the existing `NewSessionPanel` flow.
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
            Text(
              l.chatNoSessionTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.chatNoSessionBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
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

/// Error state with a Retry button that re-runs the DM entry's refresh.
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
            Text(
              l.sessionsError,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => ref
                  .read(conversationListProvider(ConversationKind.dm).notifier)
                  .refresh(),
              child: Text(l.sessionsRetry),
            ),
          ],
        ),
      ),
    );
  }
}
