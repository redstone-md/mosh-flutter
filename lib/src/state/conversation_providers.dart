/// One snapshot provider, one list provider and one invalidate switch for
/// every conversation kind.
///
/// A DM, a channel and a group read back three different generated types, so
/// something has to name the kind. The invalidate switch is named here and
/// nowhere else: [invalidateConversation] re-reads the snapshot a kind names,
/// and the list family reads the list a kind names, so a new kind adds one
/// arm to each of the two switches in this file plus one in
/// [unreadCounts] (`unread_providers.dart`) -- instead of three edits in
/// three files, with a fourth copy growing in whatever screen happens to
/// refresh a conversation this month.
///
/// The three helpers take a torn-off `read` / `invalidate`
/// ([ConversationReader] / [ConversationInvalidator]) instead of a `Ref`, so
/// a provider body and a widget callback share the one branch -- Riverpod 3
/// keeps `Ref` and `WidgetRef` unrelated types, and both of them tear off
/// into these two shapes.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderListenable, ProviderOrFamily;

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelListSnapshot, ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionListSnapshot, SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupListSnapshot, GroupSnapshot;
import 'package:mosh/src/state/channel_group_providers.dart'
    show channelSnapshotProvider, groupSnapshotProvider;
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;

/// One kind's conversation list, whatever kind it is.
///
/// The three subclasses exist so a caller with an untyped list can ask for
/// the rows it wants without naming the kind again: [sessionsOf],
/// [channelsOf] and [groupsOf] below match on the subclass.
@immutable
sealed class ConversationList {
  const ConversationList();
}

/// The DM sessions.
@immutable
final class DmConversationList extends ConversationList {
  const DmConversationList(this.snapshot);

  final SessionListSnapshot snapshot;
}

/// The channels.
@immutable
final class ChannelConversationList extends ConversationList {
  const ChannelConversationList(this.snapshot);

  final ChannelListSnapshot snapshot;
}

/// The private and org groups.
@immutable
final class GroupConversationList extends ConversationList {
  const GroupConversationList(this.snapshot);

  final GroupListSnapshot snapshot;
}

/// Server state: every conversation of one kind. One provider for all three
/// kinds -- the kind is the family arg, so each kind still carries its own
/// `AsyncValue` and refreshes on its own.
final conversationListProvider = AsyncNotifierProvider.family<
    ConversationListNotifier, ConversationList, ConversationKind>(
  ConversationListNotifier.new,
);

class ConversationListNotifier extends AsyncNotifier<ConversationList> {
  ConversationListNotifier(this.kind);

  /// Which kind this entry reads.
  final ConversationKind kind;

  @override
  Future<ConversationList> build() => _read(ref.watch(gatewayProvider));

  /// Re-runs the server query after a mutation. A guard-swap, so the rail
  /// never flashes a spinner on a refresh.
  Future<void> refresh() async =>
      state = await AsyncValue.guard(() => _read(ref.read(gatewayProvider)));

  /// [gateway] is passed in rather than read inside, so `build` can watch
  /// the seam (a wired-backend swap re-reads every list) while `refresh`
  /// reads it once.
  Future<ConversationList> _read(Gateway gateway) async => switch (kind) {
        ConversationKind.dm => DmConversationList(await gateway.listSessions()),
        ConversationKind.channel =>
          ChannelConversationList(await gateway.listChannels()),
        ConversationKind.group =>
          GroupConversationList(await gateway.listGroups()),
      };
}

/// Reads a provider. `Ref.read` and `WidgetRef.read` both tear off into this.
typedef ConversationReader = T Function<T>(ProviderListenable<T> provider);

/// Invalidates a provider. `Ref.invalidate` and `WidgetRef.invalidate` both
/// tear off into this.
typedef ConversationInvalidator = void Function(ProviderOrFamily provider);

/// Re-reads every kind's list, in parallel. The auto-poll loop and the org
/// actions ask for all three, so they loop over the kinds instead of naming
/// them one by one.
Future<void> refreshConversationLists(ConversationReader read) => Future.wait(
      <Future<void>>[
        for (final kind in ConversationKind.values)
          read(conversationListProvider(kind).notifier).refresh(),
      ],
    );

/// Re-reads one conversation's snapshot. The one branch of this shape in the
/// state layer: each kind keeps its own snapshot family, and this is where a
/// new kind adds its arm.
void invalidateConversation(
  ConversationInvalidator invalidate,
  ConversationRef conversation,
) {
  switch (conversation.kind) {
    case ConversationKind.dm:
      invalidate(activeSessionProvider(conversation.id));
    case ConversationKind.channel:
      invalidate(channelSnapshotProvider(conversation.id));
    case ConversationKind.group:
      invalidate(groupSnapshotProvider(conversation.id));
  }
}

/// [invalidateConversation] plus the rail list that shows this conversation.
///
/// A DM's rail row carries its last message, so a DM re-reads its list too;
/// a channel and a group row carry a name only, so their lists re-read with
/// the rail ([refreshConversationLists]) and not on every send.
void refreshConversation(
  ConversationInvalidator invalidate,
  ConversationRef conversation,
) {
  invalidateConversation(invalidate, conversation);
  if (conversation.kind case ConversationKind.dm) {
    invalidate(conversationListProvider(ConversationKind.dm));
  }
}

/// The DMs in [list], or none when it is another kind, is still loading, or
/// is in error. The rail degrades a missing slice to no rows, never to an
/// error screen.
List<SessionSnapshot> sessionsOf(ConversationList? list) => switch (list) {
      DmConversationList(:final snapshot) => snapshot.sessions,
      _ => const <SessionSnapshot>[],
    };

/// The channels in [list], or none when it is another kind, is still
/// loading, or is in error.
List<ChannelSnapshot> channelsOf(ConversationList? list) => switch (list) {
      ChannelConversationList(:final snapshot) => snapshot.channels,
      _ => const <ChannelSnapshot>[],
    };

/// The groups in [list], or none when it is another kind, is still loading,
/// or is in error.
List<GroupSnapshot> groupsOf(ConversationList? list) => switch (list) {
      GroupConversationList(:final snapshot) => snapshot.groups,
      _ => const <GroupSnapshot>[],
    };

/// One conversation's snapshot, keyed by its target. Two targets of the same
/// kind and id are equal, so the family hands back the same entry.
///
/// It does not poll. It watches the kind provider the app already has and
/// maps the result into [ConversationSnapshot]. That keeps one poll per
/// conversation and keeps [invalidateConversation] working exactly as before:
/// the kind provider refreshes, and this one follows.
final conversationSnapshotProvider =
    FutureProvider.family<ConversationSnapshot, AnyConversationTarget>(
  (ref, target) async => switch (target) {
    DmTarget() => DmConversation(
        target,
        await ref.watch(activeSessionProvider(target.id).future),
      ),
    ChannelTarget() => ChannelConversation(
        target,
        await ref.watch(channelSnapshotProvider(target.id).future),
      ),
    GroupTarget() => GroupConversation(
        target,
        await ref.watch(groupSnapshotProvider(target.id).future),
      ),
  },
);
