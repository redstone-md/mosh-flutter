// Org-roster rail actions -- the Flutter mirror of React's `use-orgs.ts`
// callbacks that SessionScreen wires into [OrgSection]. Mirrors React's
// per-action callbacks (leaveOrg, openMemberDm, acceptDmOffer, ...) 1:1.
//
// Each action is reduced to its own bridge-facade call and the route it
// lands on
// (an [_OrgLanding]); [_runOrgAction] owns everything else: the busy flag,
// the refresh, the mounted check, the error toast and the navigation. One
// action jumps instead of landing -- a member who already has a linked DM
// needs no call, so it needs no refresh and cannot be stopped by a re-read
// it never needed.
//
// Two things fall out of the envelope owning the refresh, both deliberate:
// the two dismisses re-read every rail list (they used to re-read only the
// orgs), and the linked-DM jump re-reads nothing.
//
// The invite settings (displayName/listenPort/staticPeer) come from
// inviteFlowProvider, the same settings source onboarding uses (ADR 0010
// DRY), and reach an action as an [_OrgInvite].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/org_runtime.dart' show OrgSnapshot, OrgMemberView;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/org_providers.dart'
    show orgsProvider, orgOperationBusProvider;
import 'package:mosh/src/state/conversation_providers.dart'
    show refreshConversationLists;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

/// The settings an org action mints an invite with.
typedef _OrgInvite = ({String displayName, int listenPort, String? staticPeer});

/// The thought one org action carries: its bridge-facade call, and where
/// it lands.
typedef _OrgAction = Future<_OrgLanding> Function(_OrgInvite invite);

/// Where an org action lands, and whether the rail must re-read first.
final class _OrgLanding {
  /// Nowhere to go: the row this action removed leaves the rail on the
  /// refresh (leave, the two dismisses).
  const _OrgLanding.stay()
      : route = null,
        needsRefresh = true;

  /// Open [route] once the rail has re-read what this action created.
  const _OrgLanding.land(this.route) : needsRefresh = true;

  /// Open [route] now: the action changed nothing, so there is nothing to
  /// re-read and nothing that can fail between the tap and the screen.
  const _OrgLanding.jump(this.route) : needsRefresh = false;

  final String? route;
  final bool needsRefresh;
}

/// The one envelope all seven org actions run in.
///
/// Marks the org busy, runs [action], re-reads the rail lists, lands on the
/// route [action] returned, and turns any failure into a snack bar --
/// identically for all seven, so a caller cannot get one of those steps
/// half right.
Future<void> _runOrgAction(
  BuildContext context,
  WidgetRef ref, {
  required String orgPubkey,
  required _OrgAction action,
}) async {
  ref.read(orgOperationBusProvider.notifier).start(orgPubkey);
  try {
    final landing = await action(_inviteOf(ref));
    if (landing.needsRefresh) await _refreshAll(ref);
    if (!context.mounted) return;
    final route = landing.route;
    if (route != null) context.go(route);
  } catch (e) {
    if (!context.mounted) return;
    showActionErrorSnackBar(context, e);
  } finally {
    ref.read(orgOperationBusProvider.notifier).finish(orgPubkey);
  }
}

/// Leave an org (React leaveOrg). The org row leaves the rail on the
/// refresh; nothing to open.
Future<void> leaveOrgAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
) =>
    _runOrgAction(context, ref, orgPubkey: org.orgPubkey, action: (_) async {
      await ref.read(bridgeFacadeProvider).leaveOrg(orgPubkey: org.orgPubkey);
      return const _OrgLanding.stay();
    });

/// Open a DM with a roster member (React openMemberDm): jump to the linked
/// session if one exists, else send an org DM offer + land on the new DM.
Future<void> openMemberDmAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
  OrgMemberView member,
) async {
  // Not one of the envelope's steps: tapping yourself is no action at all.
  if (member.isSelf) return;
  await _runOrgAction(context, ref, orgPubkey: org.orgPubkey,
      action: (invite) async {
    // The one lookup this action owns: an existing linked DM is a jump,
    // not a new offer.
    final linked = _linkedSessionId(org, member);
    if (linked != null) return _OrgLanding.jump(AppRoutes.dmFor(linked));
    final offered = await ref.read(bridgeFacadeProvider).sendOrgDmOffer(
          orgPubkey: org.orgPubkey,
          targetPeerId: member.mossPeerId,
          displayName: invite.displayName,
          listenPort: invite.listenPort,
          staticPeer: invite.staticPeer,
        );
    return _OrgLanding.land(AppRoutes.dmFor(offered.sessionId));
  });
}

/// Accept an org DM offer (React acceptDmOffer) + land on the new DM.
Future<void> acceptOrgDmOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) =>
    _runOrgAction(context, ref, orgPubkey: orgPubkey, action: (invite) async {
      final session = await ref.read(bridgeFacadeProvider).acceptOrgDmOffer(
            orgPubkey: orgPubkey,
            offerId: offerId,
            displayName: invite.displayName,
            listenPort: invite.listenPort,
            staticPeer: invite.staticPeer,
          );
      return _OrgLanding.land(AppRoutes.dmFor(session.sessionId));
    });

/// Dismiss an org DM offer (React dismissDmOffer). The offer row leaves the
/// roster on the refresh; nothing to open.
Future<void> dismissOrgDmOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) =>
    _runOrgAction(context, ref, orgPubkey: orgPubkey, action: (_) async {
      await ref.read(bridgeFacadeProvider).dismissOrgDmOffer(
            orgPubkey: orgPubkey,
            offerId: offerId,
          );
      return const _OrgLanding.stay();
    });

/// Accept an org group offer (React acceptGroupOffer) + land on the group.
Future<void> acceptOrgGroupOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) =>
    _runOrgAction(context, ref, orgPubkey: orgPubkey, action: (invite) async {
      final group = await ref.read(bridgeFacadeProvider).acceptOrgGroupOffer(
            orgPubkey: orgPubkey,
            offerId: offerId,
            displayName: invite.displayName,
            listenPort: invite.listenPort,
            staticPeer: invite.staticPeer,
          );
      return _OrgLanding.land(AppRoutes.groupFor(group.groupId));
    });

/// Dismiss an org group offer (React dismissGroupOffer). The offer row
/// leaves the roster on the refresh; nothing to open.
Future<void> dismissOrgGroupOfferAction(
  BuildContext context,
  WidgetRef ref,
  String orgPubkey,
  String offerId,
) =>
    _runOrgAction(context, ref, orgPubkey: orgPubkey, action: (_) async {
      await ref.read(bridgeFacadeProvider).dismissOrgGroupOffer(
            orgPubkey: orgPubkey,
            offerId: offerId,
          );
      return const _OrgLanding.stay();
    });

/// Create an org-bound group + offer it to every non-self roster member
/// (React createOrgGroup), then land on the new group.
Future<void> createOrgGroupAction(
  BuildContext context,
  WidgetRef ref,
  OrgSnapshot org,
  String label,
) =>
    _runOrgAction(context, ref, orgPubkey: org.orgPubkey,
        action: (invite) async {
      final created = await ref.read(bridgeFacadeProvider).createOrgGroup(
            orgPubkey: org.orgPubkey,
            label: label.trim().isEmpty ? null : label.trim(),
            // The one list this action owns: the whole roster but us.
            memberPeerIds: _invitees(org),
            displayName: invite.displayName,
            listenPort: invite.listenPort,
            staticPeer: invite.staticPeer,
          );
      return _OrgLanding.land(AppRoutes.groupFor(created.groupId));
    });

/// The session [member] already has a DM with in [org], if any. A link
/// without a session id is an offer in flight, not a conversation to open.
String? _linkedSessionId(OrgSnapshot org, OrgMemberView member) {
  for (final link in org.dmLinks) {
    final sessionId = link.sessionId;
    if (link.peerId == member.mossPeerId &&
        sessionId != null &&
        sessionId.isNotEmpty) {
      return sessionId;
    }
  }
  return null;
}

/// Everyone a new org group is offered to: the roster minus us.
List<String> _invitees(OrgSnapshot org) => org.members
    .where((m) => !m.isSelf)
    .map((m) => m.mossPeerId)
    .toList(growable: false);

_OrgInvite _inviteOf(WidgetRef ref) {
  final flow = ref.read(inviteFlowProvider);
  return (
    displayName: flow.senderDisplayName,
    listenPort: flow.listenPort,
    staticPeer: flow.staticPeer,
  );
}

Future<void> _refreshAll(WidgetRef ref) async {
  await Future.wait([
    ref.read(orgsProvider.notifier).refresh(),
    refreshConversationLists(ref.read),
  ]);
}
