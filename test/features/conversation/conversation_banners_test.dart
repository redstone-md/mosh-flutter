// The notice above a channel or a group says what the conversation is. It
// comes from the target, not from a read, so it is on screen from the first
// frame, before anything has been read.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/rust/channel_runtime.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

const String _dmId = 'dm-banner';
const String _channelName = 'chan-banner';
const String _groupId = 'group-banner';

/// Mounts [screen] with a read that never finishes, and draws one frame.
/// Settling is not an option: the loading spinner never stops animating.
Future<void> _pumpStillLoading(
  WidgetTester tester,
  Widget screen,
  Override neverResolves,
) =>
    pumpScreen(
      tester,
      screen,
      overrides: [
        gatewayProvider.overrideWithValue(ScriptableGateway()),
        neverResolves,
      ],
      settle: false,
    );

void main() {
  testWidgets('the channel notice is there before the first read lands',
      (tester) async {
    await _pumpStillLoading(
      tester,
      const ChannelScreen(name: _channelName),
      channelSnapshotProvider(_channelName)
          .overrideWith((ref) => Completer<ChannelSnapshot>().future),
    );

    expect(find.text('Public channel'), findsOneWidget);
  });

  testWidgets('the group notice is there before the first read lands',
      (tester) async {
    await _pumpStillLoading(
      tester,
      const GroupScreen(groupId: _groupId),
      groupSnapshotProvider(_groupId)
          .overrideWith((ref) => Completer<GroupSnapshot>().future),
    );

    expect(find.text('End-to-end encrypted group'), findsOneWidget);
  });

  testWidgets('a DM has no notice', (tester) async {
    await _pumpStillLoading(
      tester,
      const DmScreen(sessionId: _dmId),
      activeSessionProvider(_dmId)
          .overrideWith((ref) => Completer<SessionSnapshot>().future),
    );

    expect(find.text('Public channel'), findsNothing);
    expect(find.text('End-to-end encrypted group'), findsNothing);
  });
}
