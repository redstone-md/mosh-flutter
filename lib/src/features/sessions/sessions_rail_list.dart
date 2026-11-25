import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/features/conversation/chat_row_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/features/sessions/org_actions.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/rail_notice.dart';
import 'package:mosh/src/features/shared/avatar.dart';
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
    final compact = RailCompactScope.of(context);
    final visible = recentRailEntries(entries, l, query: query, kind: kind);
    final empty =
        status == null && offers.isEmpty && entries.isEmpty && orgs.isEmpty;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          refreshConversationLists(ref.read),
          ref.read(orgsProvider.notifier).refresh(),
        ]);
      },
      child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: kRailPadding),
          children: [
            if (status case final status?) status,
            ..._offers(context, ref, offers, l, compact: compact),
            for (final entry in visible) _row(ref, entry),
            // The collapsed list has no room for words: its New button is
            // the empty list's only action.
            if (!compact && empty)
              RailNotice(
                  title: l.chatListNoChatsTitle, detail: l.chatListNoChatsBody)
            else if (!compact && visible.isEmpty && entries.isNotEmpty)
              _noMatch(l),
            if (compact)
              for (final org in orgs) ...[
                const RailDivider(),
                CompactExpandItem(
                    leading: Avatar(name: org.orgName, radius: 24),
                    name: org.orgName),
              ]
            else
              ..._orgSections(context, ref, orgs, l),
          ]),
    );
  }

  Widget _row(WidgetRef ref, RailEntry entry) {
    final chrome = _chrome(ref, entry);
    return ChatRowMenu(
        entry: entry,
        builder: (context, menuOpen) =>
            entry.buildRow(context, chrome, menuOpen: menuOpen));
  }

  /// Nothing passes the search, or with no search the filter by kind.
  Widget _noMatch(AppLocalizations l) {
    final search = query.trim();
    return search.isEmpty
        ? RailNotice(title: l.chatListEmpty)
        : RailNotice(
            title: l.chatListNoResults(search),
            detail: l.chatListNoResultsBody);
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
    if (conversation == null) return _noChrome;
    final key = conversation.key;
    final unread = ref.watch(unreadLifecycleProvider);
    final active = ref.watch(activeConversationKeyProvider);
    return (
      unreadCount: unread[key] ?? 0,
      active: key == active,
      // The badge hides once the selected conversation is the active one;
      // the core clears its count when the screen marks it viewed.
      onSelect: () => ref.read(activeConversationKeyProvider.notifier).set(key),
    );
  }

  List<Widget> _offers(BuildContext context, WidgetRef ref,
      List<PendingDmOffer> offers, AppLocalizations l,
      {required bool compact}) {
    if (offers.isEmpty) return const [];
    return [
      if (!compact)
        Padding(
            padding: const EdgeInsets.symmetric(
                vertical: MoshSpace.s1, horizontal: MoshSpace.s3),
            child: Text(l.chatListInvitations,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: MoshColors.of(context).onSurfaceMuted))),
      for (final offer in offers)
        OfferRailEntry(
          pending: offer,
          onAccept: () => acceptOfferAction(context, ref, offer),
          onDismiss: () => dismissOfferAction(context, ref, offer),
        ).buildRow(context, _noChrome),
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

/// The chrome of a row that opens no conversation.
const RailRowChrome _noChrome = (unreadCount: 0, active: false, onSelect: null);
