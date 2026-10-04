import 'package:flutter/material.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/features/conversation/chat_row_menu.dart';
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
    show
        channelsOf,
        conversationListProvider,
        groupsOf,
        refreshConversationLists;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/state/dm_offer_providers.dart';
import 'package:mosh/src/state/org_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';

/// Invitations, then recent conversations, then the existing org sections.
class SessionsRailList extends ConsumerWidget {
  const SessionsRailList({
    super.key,
    required this.dmSessions,
    this.query = '',
    this.kind,
    this.status,
  });
  final List<SessionSnapshot> dmSessions;
  final String query;
  final ConversationKind? kind;
  final Widget? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final orgs = ref.watch(orgsProvider).value ?? const <OrgSnapshot>[];
    final offers = ref.watch(pendingDmOffersProvider);
    final entries = _entries(ref);
    if (status == null && offers.isEmpty && entries.isEmpty && orgs.isEmpty) {
      return _EmptyState(onStart: () => openNewSessionAction(context, ref));
    }
    final visible = recentRailEntries(entries, l, query: query, kind: kind);
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          refreshConversationLists(ref.read),
          ref.read(orgsProvider.notifier).refresh(),
        ]);
      },
      child: ListView(
          padding: const EdgeInsetsDirectional.only(end: 12),
          children: [
            if (status case final status?) status,
            ..._offers(context, ref, offers, l),
            for (final entry in visible)
              ChatRowMenu(
                  entry: entry,
                  child: entry.buildRow(context, _chrome(ref, entry))),
            if (visible.isEmpty && entries.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.chatListEmpty)),
            ..._orgSections(context, ref, orgs, l),
          ]),
    );
  }

  List<RailEntry> _entries(WidgetRef ref) {
    final channels = channelsOf(
        ref.watch(conversationListProvider(ConversationKind.channel)).value);
    final groups = groupsOf(
        ref.watch(conversationListProvider(ConversationKind.group)).value);
    final names = ref.watch(chatNamesProvider).value?.entries ?? [];
    final aliases = {for (final e in names) e.conversationKey: e.name};
    final revoked = ref.watch(revokedDmBadgesProvider);
    return [
      for (final s in dmSessions)
        DmRailEntry(s,
            revokedOrgName: revoked[s.sessionId],
            personalName: aliases['dm:${s.sessionId}']),
      for (final g in groups) GroupRailEntry(g),
      for (final c in channels)
        ChannelRailEntry(c, personalName: aliases['channel:${c.name}']),
    ];
  }

  RailRowChrome _chrome(WidgetRef ref, RailEntry entry) {
    final conversation = entry.ref;
    if (conversation == null) {
      return (unreadCount: 0, active: false, onSelect: null);
    }
    final key = conversation.key;
    final unread = ref.watch(unreadLifecycleProvider);
    final active = ref.watch(activeConversationKeyProvider);
    return (
      unreadCount: unread[key] ?? 0,
      active: key == active,
      onSelect: () {
        ref.read(unreadLifecycleProvider.notifier).clearUnread(key);
        ref.read(activeConversationKeyProvider.notifier).set(key);
      },
    );
  }

  List<Widget> _offers(BuildContext context, WidgetRef ref,
      List<PendingDmOffer> offers, AppLocalizations l) {
    if (offers.isEmpty) return const [];
    return [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(l.chatListInvitations,
              style: Theme.of(context).textTheme.labelMedium)),
      for (final offer in offers)
        OfferRailEntry(
          pending: offer,
          onAccept: () => acceptOfferAction(context, ref, offer),
          onDismiss: () => dismissOfferAction(context, ref, offer),
        ).buildRow(context, (unreadCount: 0, active: false, onSelect: null)),
      const RailDivider(),
    ];
  }
}

List<Widget> _orgSections(BuildContext context, WidgetRef ref,
    List<OrgSnapshot> orgs, AppLocalizations l) {
  final busy = ref.watch(orgOperationBusProvider);
  return [
    for (final org in orgs) ...[
      const RailDivider(),
      OrgSection(
        org: org,
        busy: busy.contains(org.orgPubkey),
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
    ]
  ];
}

/// Empty state for the sessions list. Reuses the
/// `chatNoSessionTitle` + `chatNoSessionBody` welcome, with the
/// `shellNewSession` button, the same action and label as the rail's
/// start button.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
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
              label: Text(l.shellNewSession),
            ),
          ],
        ),
      )),
    );
  }
}
