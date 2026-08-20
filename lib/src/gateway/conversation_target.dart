// Which conversation an action is for: a DM, a channel, or a group.
//
// The Gateway takes one of these instead of carrying a DM, a channel and a
// group copy of every method. Each kind knows the snapshot type it polls
// back, so one `Gateway.poll` still returns the right type to the caller.

import 'package:mosh/src/rust/channel_runtime.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;

/// A conversation the app can read, send to, and leave.
///
/// [TSnapshot] is the snapshot type this kind polls back. Two targets are
/// equal when they are the same kind with the same [id], so a screen can ask
/// "is this still my conversation?" with `==`.
sealed class ConversationTarget<TSnapshot> {
  const ConversationTarget(this.id);

  /// The DM session id, the channel name, or the group id.
  final String id;

  /// Reads this conversation's snapshot. Each kind calls its own method on
  /// [reader]; that is what keeps `Gateway.poll` a single typed method.
  Future<TSnapshot> readSnapshot(ConversationSnapshotReader reader);

  @override
  bool operator ==(Object other) =>
      other is ConversationTarget<TSnapshot> &&
      other.runtimeType == runtimeType &&
      other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);

  @override
  String toString() => '$runtimeType($id)';
}

/// A target of any kind, for the calls whose snapshot type does not matter.
typedef AnyConversationTarget = ConversationTarget<Object?>;

/// A private DM between two people. The [id] is the session id.
final class DmTarget extends ConversationTarget<SessionSnapshot> {
  const DmTarget(super.id);

  @override
  Future<SessionSnapshot> readSnapshot(ConversationSnapshotReader reader) =>
      reader.dmSnapshot(id);
}

/// A conversation that can carry DM offers. A DM cannot hold one, so
/// `Gateway.dismissDmOffer` takes this narrower type and the DM case never
/// reaches it.
sealed class DmOfferHost<TSnapshot> extends ConversationTarget<TSnapshot> {
  const DmOfferHost(super.id);
}

/// A public channel. The [id] is the channel name.
final class ChannelTarget extends DmOfferHost<ChannelSnapshot> {
  const ChannelTarget(super.id);

  @override
  Future<ChannelSnapshot> readSnapshot(ConversationSnapshotReader reader) =>
      reader.channelSnapshot(id);
}

/// A private or org group. The [id] is the group id.
final class GroupTarget extends DmOfferHost<GroupSnapshot> {
  const GroupTarget(super.id);

  @override
  Future<GroupSnapshot> readSnapshot(ConversationSnapshotReader reader) =>
      reader.groupSnapshot(id);
}

/// One snapshot read per conversation kind. Gateway implementations provide
/// it, and each target picks the method that matches its kind. Callers never
/// touch it -- they call `Gateway.poll(target)`.
abstract interface class ConversationSnapshotReader {
  Future<SessionSnapshot> dmSnapshot(String sessionId);
  Future<ChannelSnapshot> channelSnapshot(String name);
  Future<GroupSnapshot> groupSnapshot(String groupId);
}
