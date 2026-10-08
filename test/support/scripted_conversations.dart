// The in-memory conversation state both test doubles see.
//
// In production one Rust runtime holds every conversation and the two Dart
// surfaces (the Gateway seam and the bridge facade) are views over it. The
// fakes mirror that: `ScriptableGateway` owns one of these, and a test that
// wires both doubles hands the same instance to `ScriptableBridge`, so a
// seeded session is what `listSessions` serves AND what a DM poll reads, and
// an accepted invite inserts the session the pushed screen then polls.
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show InviteCreated, SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupSnapshot, GroupNameStatus;

/// The seeded DM sessions, channels and groups, keyed the way the runtime
/// keys them (session id, channel name, group id). Seeding replaces whatever
/// was there before, so a test can seed again to change what the next read
/// sees.
class ScriptedConversations {
  final names = <String, String>{};
  final Map<String, SessionSnapshot> sessions = {};
  final Map<String, InviteCreated> pendingInvites = {};
  final Set<String> hiddenSessions = {};
  final Map<String, ChannelSnapshot> channels = {};
  final Map<String, GroupSnapshot> groups = {};

  void renameGroup(GroupSnapshot group, String name) {
    groups[group.groupId] = GroupSnapshot(
      groupId: group.groupId,
      meshId: group.meshId,
      label: name,
      displayName: group.displayName,
      deviceFingerprint: group.deviceFingerprint,
      creatorFingerprint: group.creatorFingerprint,
      isAdmin: group.isAdmin,
      nameStatus: const GroupNameStatus(pending: false),
      state: group.state,
      memberCount: group.memberCount,
      inviteUri: group.inviteUri,
      messages: group.messages,
      attachments: group.attachments,
      dmOffers: group.dmOffers,
      mesh: group.mesh,
      events: group.events,
      needsRejoin: group.needsRejoin,
      orgPubkey: group.orgPubkey,
      memberPeerIds: group.memberPeerIds,
      typingMembers: group.typingMembers,
    );
  }

  void seedSessions(Iterable<SessionSnapshot> seeded) {
    sessions
      ..clear()
      ..addEntries(seeded.map((s) => MapEntry(s.sessionId, s)));
  }

  void seedChannels(Iterable<ChannelSnapshot> seeded) {
    channels
      ..clear()
      ..addEntries(seeded.map((c) => MapEntry(c.name, c)));
  }

  void seedGroups(Iterable<GroupSnapshot> seeded) {
    groups
      ..clear()
      ..addEntries(seeded.map((g) => MapEntry(g.groupId, g)));
  }
}
