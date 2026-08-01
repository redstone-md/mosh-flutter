// Org-roster rail action helpers -- the Flutter mirror of React's
// `use-orgs.ts` callbacks that SessionScreen wires into [OrgSection]. Each
// helper hits the Gateway seam, refreshes the org-roster + session/group
// lists, and navigates to the resulting chat (DM or group). Mirrors React:
//   - leaveOrg        -> gateway.leaveOrg + refreshOrgs + refresh(quiet)
//   - openMemberDm     -> use the existing dm_link session_id or
//                        sendOrgDmOffer, then setActive(dm)
//   - acceptDmOffer   -> gateway.acceptOrgDmOffer + setActive(dm)
//   - dismissDmOffer  -> gateway.dismissOrgDmOffer + refreshOrgs
//   - acceptGroupOffer-> gateway.acceptOrgGroupOffer + setActive(group)
//   - dismissGroupOffer-> gateway.dismissOrgGroupOffer + refreshOrgs
//   - createOrgGroup  -> gateway.createOrgGroup (invite all non-self
//                        roster members) + setActive(group)
//
// The `requestBase` (displayName/listenPort/staticPeer) comes from
// inviteFlowProvider, the same settings source onboarding uses (DRY). A
// transient SnackBar surfaces errors (mirrors React run("offer", onError)).

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/org_runtime.dart'
    show OrgSnapshot, OrgMemberView;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/org_providers.dart' show orgsProvider;
import 'package:mosh/src/state/session_providers.dart'
    show inviteFlowProvider, sessionListProvider;
import 'package:mosh/src/state/channel_group_providers.dart'
    show channelListProvider, groupListProvider;

Future<void> _refreshAll(WidgetRef ref) async {
  await Future.wait([
    ref.read(orgsProvider.notifier).refresh(),
    ref.read(sessionListProvider.notifier).refresh(),
    ref.read(channelListProvider.notifier).refresh(),
    ref.read(groupListProvider.notifier).refresh(),
  ]);
}

void _error(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}

/// Leave an org (React leaveOrg).
Future<void> leaveOrgAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  try {
    await ref.read(gatewayProvider).leaveOrg(orgPubkey: org.orgPubkey);
    await _refreshAll(ref);
  } catch (e) {
    if (!context.mounted) return;
    scaffold.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

/// Open a DM with a roster member (React openMemberDm): jump to the linked
/// session if one exists, else send an org DM offer + jump to the new DM.
Future<void> openMemberDmAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
  OrgMemberView member,
) async {
  if (member.isSelf) return;
  final flow = ref.read(inviteFlowProvider);
  final gateway = ref.read(gatewayProvider);
  try {
    // Existing linked DM: jump straight to it.
    for (final link in org.dmLinks) {
      if (link.peerId == member.mossPeerId &&
          link.sessionId != null &&
          link.sessionId!.isNotEmpty) {
        if (!context.mounted) return;
        context.go(AppRoutes.dmFor(link.sessionId!));
        return;
      }
    }
    final invite = await gateway.sendOrgDmOffer(
      orgPubkey: org.orgPubkey,
      targetPeerId: member.mossPeerId,
      displayName: flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
      listenPort: flow.listenPort,
      staticPeer: flow.staticPeer,
    );
    await _refreshAll(ref);
    if (!context.mounted) return;
    context.go(AppRoutes.dmFor(invite.sessionId));
  } catch (e) {
    _error(context, e);
  }
}

/// Accept an org DM offer (React acceptDmOffer) + jump to the new DM.
Future<void> acceptOrgDmOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) async {
  final flow = ref.read(inviteFlowProvider);
  try {
    final session = await ref.read(gatewayProvider).acceptOrgDmOffer(
          orgPubkey: orgPubkey,
          offerId: offerId,
          displayName: flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
          listenPort: flow.listenPort,
          staticPeer: flow.staticPeer,
        );
    await _refreshAll(ref);
    if (!context.mounted) return;
    context.go(AppRoutes.dmFor(session.sessionId));
  } catch (e) {
    _error(context, e);
  }
}

/// Dismiss an org DM offer (React dismissDmOffer).
Future<void> dismissOrgDmOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) async {
  try {
    await ref.read(gatewayProvider)
        .dismissOrgDmOffer(orgPubkey: orgPubkey, offerId: offerId);
    await ref.read(orgsProvider.notifier).refresh();
  } catch (e) {
    if (!context.mounted) return;
    _error(context, e);
  }
}

/// Accept an org group offer (React acceptGroupOffer) + jump to the group.
Future<void> acceptOrgGroupOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) async {
  final flow = ref.read(inviteFlowProvider);
  try {
    final group = await ref.read(gatewayProvider).acceptOrgGroupOffer(
          orgPubkey: orgPubkey,
          offerId: offerId,
          displayName: flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
          listenPort: flow.listenPort,
          staticPeer: flow.staticPeer,
        );
    await _refreshAll(ref);
    if (!context.mounted) return;
    context.go(AppRoutes.groupFor(group.groupId));
  } catch (e) {
    _error(context, e);
  }
}

/// Dismiss an org group offer (React dismissGroupOffer).
Future<void> dismissOrgGroupOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) async {
  try {
    await ref.read(gatewayProvider)
        .dismissOrgGroupOffer(orgPubkey: orgPubkey, offerId: offerId);
    await ref.read(orgsProvider.notifier).refresh();
  } catch (e) {
    if (!context.mounted) return;
    _error(context, e);
  }
}

/// Create an org-bound group + offer it to every non-self roster member
/// (React createOrgGroup), then jump to the new group.
Future<void> createOrgGroupAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
  String label,
) async {
  final flow = ref.read(inviteFlowProvider);
  try {
    final invited = org.members
        .where((m) => !m.isSelf)
        .map((m) => m.mossPeerId)
        .toList(growable: false);
    final created = await ref.read(gatewayProvider).createOrgGroup(
          orgPubkey: org.orgPubkey,
          label: label.trim().isEmpty ? null : label.trim(),
          memberPeerIds: invited,
          displayName: flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
          listenPort: flow.listenPort,
          staticPeer: flow.staticPeer,
        );
    await _refreshAll(ref);
    if (!context.mounted) return;
    context.go(AppRoutes.groupFor(created.groupId));
  } catch (e) {
    _error(context, e);
  }
}
