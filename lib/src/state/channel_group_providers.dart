// One channel's and one group's snapshot -- the server state the channel and
// group screens read. The LISTS of channels and groups are not here:
// [conversationListProvider] serves all three kinds, so the kind branch
// lives in one module (`conversation_providers.dart`).
//
// Per ADR 0010: server/async state lives in a provider family (the
// TanStack-Query analogue -- loading/data/error flows through `AsyncValue`).
// Both providers consume the `gatewayProvider` seam (ADR 0013), never a
// concrete `Gateway`, so the wired backend is a single provider swap and
// both the test gateway and `RealBridgeGateway` satisfy this file.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';

import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;
import 'package:mosh/src/state/gateway_provider.dart';

/// Server state: one channel's snapshot, parameterized by name (channel
/// screen, S5-1). A one-shot read per watch, mirroring `activeSessionProvider`
/// 1:1 but against `Gateway.poll` with a ChannelTarget. The ChannelScreen re-polls by
/// invalidating the family entry after a send/leave (ADR 0010 family idiom).
final channelSnapshotProvider = FutureProvider.family<ChannelSnapshot, String>(
  (ref, name) => ref.watch(gatewayProvider).poll(ChannelTarget(name)),
);

/// Server state: one group's snapshot, parameterized by `groupId` (group
/// screen, the groups analogue of S5-1's ChannelScreen). A one-shot read per
/// watch, mirroring `channelSnapshotProvider` 1:1 but against
/// `Gateway.poll` with a GroupTarget. The GroupScreen re-polls by invalidating the family
/// entry after a send/leave (ADR 0010 family idiom). Keyed by `groupId`
/// (the group identity), NOT a display name -- the Rust `group_id` shape.
final groupSnapshotProvider = FutureProvider.family<GroupSnapshot, String>(
  (ref, groupId) => ref.watch(gatewayProvider).poll(GroupTarget(groupId)),
);
