// Slice-3 org-roster state surface. Backs the group screen's orgAddPrompt
// banner (the admin's "+N not in group" one-click add, spec §5). Exposes:
//   - orgsProvider: the polled list of joined orgs (listOrgs + pollOrg each).
//   - offeredGroupInvitesProvider: in-memory map groupId -> offered peer-ids
//     so the prompt neither miscounts pending invitees nor spams duplicate
//     offers per click.
//   - invitingGroupsProvider: groupIds with an in-flight invite (banner busy).
//   - orgAddPromptProvider (family by groupId): the computed prompt or null.
//
// Per ADR 0010/0013: server state via AsyncNotifier, ephemeral invite state
// via class-based Notifier (StateProvider is legacy in Riverpod v3). The org
// reads are 1:1 bridge mirrors, so they go through bridgeFacadeProvider
// (ADR 0025).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/org_runtime.dart' show OrgSnapshot;
import 'package:mosh/src/state/channel_group_providers.dart'
    show groupSnapshotProvider;
import 'package:mosh/src/state/gateway_provider.dart';

/// Server state: the joined orgs. listOrgs then
/// pollOrg each (the backend drains roster gossip on this cadence). A later
/// atomic wires an interval poll; this atomic
/// ships the one-shot read so the prompt renders on group-screen open + after
/// an invite refreshes.
final orgsProvider = AsyncNotifierProvider<OrgsNotifier, List<OrgSnapshot>>(
  OrgsNotifier.new,
);

class OrgsNotifier extends AsyncNotifier<List<OrgSnapshot>> {
  @override
  Future<List<OrgSnapshot>> build() async =>
      _poll(ref.watch(bridgeFacadeProvider));

  /// Re-run after a mutation (join/leave/inviteMembersToGroup). Riverpod
  /// invalidation is already race-safe via guard.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _poll(ref.read(bridgeFacadeProvider)));
  }

  Future<List<OrgSnapshot>> _poll(BridgeFacade bridge) async {
    final listed = await bridge.listOrgs();
    final polled = <OrgSnapshot>[];
    for (final org in listed) {
      try {
        polled.add(await bridge.pollOrg(orgPubkey: org.orgPubkey));
      } catch (_) {
        polled.add(org);
      }
    }
    return polled;
  }
}

/// In-memory map groupId -> offered peer-ids this session. Survives across
/// group-screen rebuilds within a session; reset on app restart.
final offeredGroupInvitesProvider =
    NotifierProvider<OfferedGroupInvitesNotifier, Map<String, Set<String>>>(
  OfferedGroupInvitesNotifier.new,
);

class OfferedGroupInvitesNotifier extends Notifier<Map<String, Set<String>>> {
  @override
  Map<String, Set<String>> build() => const {};

  /// Mark the peer-ids as offered for this group.
  void markInvited(String groupId, Iterable<String> memberPeerIds) {
    final next = Map<String, Set<String>>.from(state);
    final merged = Set<String>.from(next[groupId] ?? const <String>{});
    merged.addAll(memberPeerIds);
    next[groupId] = merged;
    state = next;
  }
}

/// groupIds with an in-flight inviteMembersToGroup (banner busy flag).
final invitingGroupsProvider =
    NotifierProvider<InvitingGroupsNotifier, Set<String>>(
  InvitingGroupsNotifier.new,
);

class InvitingGroupsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void start(String groupId) {
    state = Set<String>.from(state)..add(groupId);
  }

  void finish(String groupId) {
    state = Set<String>.from(state)..remove(groupId);
  }
}

/// orgPubkeys with an in-flight org operation (leave/offer/member/group).
/// The Set is keyed by orgPubkey, so only the org being operated on
/// disables, not unrelated orgs. The one org-action envelope wraps every
/// org_actions call in start/finish so an OrgSection's
/// leave/offer/member/new-group affordances stay disabled until the await +
/// refresh + navigation done (double-tap protection).
final orgOperationBusProvider =
    NotifierProvider<OrgOperationBusNotifier, Set<String>>(
  OrgOperationBusNotifier.new,
);

class OrgOperationBusNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void start(String orgPubkey) {
    state = Set<String>.from(state)..add(orgPubkey);
  }

  void finish(String orgPubkey) {
    state = Set<String>.from(state)..remove(orgPubkey);
  }
}

/// The computed orgAddPrompt for a group: null when the active user is not an
/// org admin of the group's org, or no roster members are missing; otherwise
/// {count, busy, missingPeerIds, orgPubkey} so the banner renders "+N not in
/// group" + disables while the invite is sending.
final orgAddPromptProvider =
    Provider.family<OrgAddPrompt?, String>((ref, groupId) {
  final orgs = ref.watch(orgsProvider);
  final groupAsync = ref.watch(groupSnapshotProvider(groupId));
  final offered = ref.watch(offeredGroupInvitesProvider);
  final inviting = ref.watch(invitingGroupsProvider);

  final group = groupAsync.value;
  if (group == null) return null;
  final orgPubkey = group.orgPubkey;
  if (orgPubkey == null) return null;
  final orgList = orgs.value ?? const <OrgSnapshot>[];
  OrgSnapshot? org;
  for (final o in orgList) {
    if (o.orgPubkey == orgPubkey) {
      org = o;
      break;
    }
  }
  if (org == null) return null;

  final selfIsAdmin = org.members.any((m) => m.isSelf && m.role == 'admin');
  if (!selfIsAdmin) return null;

  final alreadyOffered = offered[groupId] ?? const <String>{};
  final groupPeers = group.memberPeerIds.toSet();
  final missing = org.members
      .where((m) => !m.isSelf)
      .where((m) => !groupPeers.contains(m.mossPeerId))
      .where((m) => !alreadyOffered.contains(m.mossPeerId))
      .map((m) => m.mossPeerId)
      .toList();
  if (missing.isEmpty) return null;

  return OrgAddPrompt(
    count: missing.length,
    busy: inviting.contains(groupId),
    missingPeerIds: missing,
    orgPubkey: orgPubkey,
  );
});

/// The prompt payload for [orgAddPromptProvider]. onAdd is owned by the screen
/// (it calls bridge.orgGroupInviteMembers + updates offeredGroupInvites) so
/// the provider stays a pure read.
class OrgAddPrompt {
  const OrgAddPrompt({
    required this.count,
    required this.busy,
    required this.missingPeerIds,
    required this.orgPubkey,
  });

  final int count;
  final bool busy;
  final List<String> missingPeerIds;
  final String orgPubkey;
}
