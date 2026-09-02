// What the rail's ONE loop has to get right for every kind: a row's unread
// count, its active highlight and the conversation it opens all come from
// the key the row itself names (`RailEntry.ref.key`) -- not from a literal
// the screen spells out per kind. The screen used to write `'dm:<id>'`,
// `'channel:<name>'` and `'group:<id>'` by hand three times each; these
// tests are what stops that coming back.
//
// Setup mirrors the other rail tests: a seeded `ScriptableBridge`, a
// localized MaterialApp, and a ProviderScope whose container the test also
// reads, so the active-conversation key can be set before the first frame
// and read back after a tap.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;
import 'package:mosh/src/features/sessions/rail_item.dart' show RailItem;
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

/// One conversation of each kind: a DM with Alice, the `general` channel
/// and the `Crew` group. The rail renders one row per conversation, so the
/// title is what tells the rows apart.
const dmId = 'alice-session';
const channelName = 'general';
const groupId = 'crew-42';

/// The unread map the rail reads, keyed the way [ConversationRef] writes
/// it. Three different counts, so a row that read another row's key (or a
/// misspelled prefix) shows the wrong number instead of none.
final _unread = <String, int>{
  'dm:$dmId': 1,
  'channel:$channelName': 2,
  'group:$groupId': 3,
};

SessionSnapshot _session() => SessionSnapshot(
      sessionId: dmId,
      meshId: 'm',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: DmSessionState.connected,
      transport: PeerTransport.none,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

ChannelSnapshot _channel() => ChannelSnapshot(
      name: channelName,
      topic: 'chatter',
      meshId: 'm',
      displayName: 'me',
      deviceFingerprint: 'SELF',
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

GroupSnapshot _group() => GroupSnapshot(
      groupId: groupId,
      meshId: 'm',
      label: 'Crew',
      displayName: 'me',
      deviceFingerprint: 'SELF',
      creatorFingerprint: 'SELF',
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.from(3),
      inviteUri: null,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

/// One rail with a DM, a channel and a group in it.
ProviderContainer _rail() => ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(ScriptableBridge()
        ..seedSessions([_session()])
        ..seedChannels([_channel()])
        ..seedGroups([_group()])),
      // The lifecycle map is stubbed so the rendered counts are
      // deterministic; the rail still reads it by key, which is what is
      // under test.
      unreadLifecycleProvider.overrideWithBuild((ref, notifier) => _unread),
    ]);

/// The rail row titled [title]. Every row is a [RailItem] now, the offer
/// row included, so the title is the only thing that tells them apart.
RailItem _row(WidgetTester tester, String title) => tester
    .widgetList<RailItem>(find.byType(RailItem))
    .firstWhere((item) => item.title == title);

/// The unread count [title]'s row renders.
int _unreadOf(WidgetTester tester, String title) =>
    (_row(tester, title).trailing! as UnreadBadge).count;

void main() {
  testWidgets('every kind reads its unread count from its own key',
      (tester) async {
    final container = _rail();
    addTearDown(container.dispose);
    await pumpScreen(tester, const SessionsScreen(), container: container);

    expect(_unreadOf(tester, 'Alice'), 1);
    expect(_unreadOf(tester, '#$channelName'), 2);
    expect(_unreadOf(tester, 'Crew'), 3);
  });

  testWidgets('every kind highlights the row its key names', (tester) async {
    // Key -> the title of the row it must highlight.
    const keys = <String, String>{
      'dm:$dmId': 'Alice',
      'channel:$channelName': '#$channelName',
      'group:$groupId': 'Crew',
    };
    for (final MapEntry(:key, :value) in keys.entries) {
      final container = _rail();
      addTearDown(container.dispose);
      // Set on the real notifier before the first pump, so the watch reads
      // the fixed value on the first build.
      container.read(activeConversationKeyProvider.notifier).set(key);
      await pumpScreen(tester, const SessionsScreen(), container: container);

      for (final title in keys.values) {
        expect(_row(tester, title).active, title == value,
            reason: '$key must highlight $value, not $title');
      }
    }
  });

  testWidgets('a tapped group row opens the key the group screen opens too',
      (tester) async {
    final container = _rail();
    addTearDown(container.dispose);
    // useRouter so the row's `context.go` resolves and the group screen
    // really opens.
    await pumpRoute(tester, AppRoutes.sessions, container: container);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    // The rail and the conversation screen must agree: one key grammar,
    // written once, read by both.
    expect(container.read(activeConversationKeyProvider), 'group:$groupId');
  });
}
