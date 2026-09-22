// Which conversation an action is for: a DM, a channel, or a group.
//
// The Gateway takes one of these instead of carrying a DM, a channel and a
// group copy of every method. Each kind knows the snapshot type it polls
// back, so one `Gateway.poll` still returns the right type to the caller.

import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;

/// The three kinds of conversation. The names are also the strings the
/// attachment streaming server keys its URLs by, so keep them in step.
///
/// This is the one kind enum in the app: the state layer, the rail and the
/// shell all name a kind with it, and [ConversationRef] owns the key
/// grammar the kinds render into. `RailItemKind`
/// (features/sessions/rail_item.dart) carries the same three names but
/// names how a row is tinted, not what a conversation is.
enum ConversationKind { dm, channel, group }

/// Which conversation: a [kind] plus the kind-local [id].
///
/// This is the address of a conversation and nothing more. It cannot read a
/// snapshot -- that is [ConversationTarget]'s job, because `Gateway.poll`
/// has to hand back a typed snapshot, so the two stay separate types.
///
/// It is also the one owner of the `kind:id` grammar: [key] renders one and
/// [tryParse] reads one back. The screens write that key into
/// `activeConversationKeyProvider` and the title bar, the shell drawer and
/// the auto-poll loop read it back, so the format can only live in one
/// place.
final class ConversationRef {
  const ConversationRef({required this.kind, required this.id})
      : assert(id.length > 0, 'id must not be empty');

  final ConversationKind kind;

  /// The DM session id, the channel name, or the group id. It may itself
  /// contain colons -- only the first one separates it from [kind].
  final String id;

  /// How the app names this conversation: `dm:<id>`, `channel:<name>` or
  /// `group:<id>`. [tryParse] reads this format back, so the two have to
  /// agree.
  String get key => '${kind.name}:$id';

  /// Reads a [key] back, or returns null when it is not one: null, a key with
  /// no kind prefix, an unknown kind, or an empty id.
  ///
  /// Only the first colon splits the kind from the id, so an id that carries
  /// colons of its own survives the round trip.
  static ConversationRef? tryParse(String? key) {
    if (key == null) return null;
    final separator = key.indexOf(':');
    if (separator <= 0) return null;
    final kind =
        ConversationKind.values.asNameMap()[key.substring(0, separator)];
    if (kind == null) return null;
    final id = key.substring(separator + 1);
    if (id.isEmpty) return null;
    return ConversationRef(kind: kind, id: id);
  }

  @override
  bool operator ==(Object other) =>
      other is ConversationRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'ConversationRef(${kind.name}:$id)';
}

/// A conversation the app can read, send to, and leave.
///
/// [TSnapshot] is the snapshot type this kind polls back. Two targets are
/// equal when they are the same kind with the same [id], so a screen can ask
/// "is this still my conversation?" with `==`.
sealed class ConversationTarget<TSnapshot> {
  const ConversationTarget(this.id);

  /// The DM session id, the channel name, or the group id.
  final String id;

  /// Which kind this is. The shared conversation UI branches on it for the
  /// few things that really do differ per kind.
  ConversationKind get kind;

  /// This conversation as a [ConversationRef], the value the state layer
  /// names conversations with.
  ConversationRef get ref => ConversationRef(kind: kind, id: id);

  /// How the app names the conversation that is open: `dm:<id>`,
  /// `channel:<name>` or `group:<id>`. `ConversationRef.tryParse` reads this
  /// format back, so the two have to agree.
  String get key => ref.key;

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
  ConversationKind get kind => ConversationKind.dm;

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
  ConversationKind get kind => ConversationKind.channel;

  @override
  Future<ChannelSnapshot> readSnapshot(ConversationSnapshotReader reader) =>
      reader.channelSnapshot(id);
}

/// A private or org group. The [id] is the group id.
final class GroupTarget extends DmOfferHost<GroupSnapshot> {
  const GroupTarget(super.id);

  @override
  ConversationKind get kind => ConversationKind.group;

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
