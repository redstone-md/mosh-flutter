// Channels/groups list server-state providers -- the Flutter mirror of the
// React `listChannels` / `listGroups` reads backing the channels and groups
// sections of the SessionRail. These are the channel/group analogues of
// `sessionListProvider` in `session_providers.dart`.
//
// Per ADR 0010: server/async state lives in `AsyncNotifierProvider<T>` (the
// TanStack-Query analogue -- loading/data/error flows through `AsyncValue`).
// Both providers consume the `gatewayProvider` seam (ADR 0013), never a
// concrete `Gateway`, so the wired backend is a single provider swap and
// both the test gateway and `RealBridgeGateway` satisfy this file.
//
// The `Gateway.listChannels` / `Gateway.listGroups` methods (commit b750a87)
// and the generated non-opaque contract types `ChannelListSnapshot` /
// `GroupListSnapshot` already exist; this atomic adds only the providers, no
// Rust / frb codegen. Wiring these providers into the SessionsScreen (and
// rendering the `ChannelRailItem` / `GroupRailItem` widgets from them) is a
// later atomic -- here the providers stand alone, ready for that wiring.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';

import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// Server state: the list of all channels (sessions-screen channels section,
/// later atomic). `AsyncValue<ChannelListSnapshot>` -- loading -> data/error
/// per ADR 0010. Mirrors `sessionListProvider` 1:1 but against
/// `Gateway.listChannels()`.
final channelListProvider =
    AsyncNotifierProvider<ChannelListNotifier, ChannelListSnapshot>(
  ChannelListNotifier.new,
);

class ChannelListNotifier extends AsyncNotifier<ChannelListSnapshot> {
  @override
  Future<ChannelListSnapshot> build() =>
      ref.watch(gatewayProvider).listChannels();

  /// Re-run the server query after a mutation (join/leave/send, later atomic).
  Future<void> refresh() async => state = await AsyncValue.guard(
        () => ref.read(gatewayProvider).listChannels(),
      );
}

/// Server state: the list of all groups (sessions-screen groups section,
/// later atomic). `AsyncValue<GroupListSnapshot>` -- loading -> data/error
/// per ADR 0010. Mirrors `sessionListProvider` 1:1 but against
/// `Gateway.listGroups()`.
final groupListProvider =
    AsyncNotifierProvider<GroupListNotifier, GroupListSnapshot>(
  GroupListNotifier.new,
);

class GroupListNotifier extends AsyncNotifier<GroupListSnapshot> {
  @override
  Future<GroupListSnapshot> build() =>
      ref.watch(gatewayProvider).listGroups();

/// Re-run the server query after a mutation (create/join/send/leave,
/// later atomic).
  Future<void> refresh() async => state = await AsyncValue.guard(
        () => ref.read(gatewayProvider).listGroups(),
      );
}

/// Server state: one channel's snapshot, parameterized by name (channel
/// screen, S5-1). A one-shot read per watch, mirroring `activeSessionProvider`
/// 1:1 but against `Gateway.poll` with a ChannelTarget. The ChannelScreen re-polls by
/// invalidating the family entry after a send/leave (ADR 0010 family idiom).
final channelSnapshotProvider =
    FutureProvider.family<ChannelSnapshot, String>(
  (ref, name) => ref.watch(gatewayProvider).poll(ChannelTarget(name)),
);

/// Server state: one group's snapshot, parameterized by `groupId` (group
/// screen, the groups analogue of S5-1's ChannelScreen). A one-shot read per
/// watch, mirroring `channelSnapshotProvider` 1:1 but against
/// `Gateway.poll` with a GroupTarget. The GroupScreen re-polls by invalidating the family
/// entry after a send/leave (ADR 0010 family idiom). Keyed by `groupId`
/// (the group identity), NOT a display name -- mirroring the Rust/React
/// `group_id` shape.
final groupSnapshotProvider =
    FutureProvider.family<GroupSnapshot, String>(
  (ref, groupId) => ref.watch(gatewayProvider).poll(GroupTarget(groupId)),
);
