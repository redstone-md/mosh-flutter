// Seeded data and the app mount for the Chats area scenes: a realistic
// chat list (DMs, groups, channels), an organisation roster, and the real
// MoshApp shell with its rail layout kept in memory.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show NativeRuntimeStatus;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/conversation/dm_offers.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/persistence.dart' show PersistenceRuntimeStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';

import '../../../test/support/desktop_window_platform.dart';
import '../../../test/support/gateway_snapshots.dart';
import '../../../test/support/message_builders.dart';
import '../../../test/support/rail.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import '../../../test/support/settings.dart';
import 'harness.dart';

const me = 'Alex';
const selfFp = 'self';

BigInt _at(int hour, int minute, {int daysAgo = 0}) {
  final now = DateTime.now();
  return BigInt.from(
      DateTime(now.year, now.month, now.day - daysAgo, hour, minute)
          .millisecondsSinceEpoch);
}

/// Unread counts the populated list shows: a few, one group, and one past 99.
const Map<String, int> chatsUnread = {
  'dm:maya': 2,
  'group:weekend': 5,
  'dm:priya': 128,
};

SessionSnapshot _dm(String id, String peer, List<(bool, String, BigInt)> chat,
        {DmSessionState state = DmSessionState.connected}) =>
    TestSnapshots.dm(
        sessionId: id,
        displayName: me,
        peerDisplayName: peer,
        state: state,
        messages: [
          for (final (i, (mine, body, at)) in chat.indexed)
            TestMessages.dm(
                fromDevice: mine ? me : peer,
                body: body,
                messageId: '$id-$i',
                sentAtMs: at,
                read: mine),
        ]);

List<SessionSnapshot> chatsDms() => [
      _dm('maya', 'Maya Chen', [
        (false, 'Coffee after the walk?', _at(9, 38)),
        (true, 'Absolutely. Riverside at 10?', _at(9, 40)),
        (false, 'See you by the bridge!', _at(9, 43)),
      ]),
      _dm('leo', 'Leo Park', [
        (false, 'Did the trail map come through?', _at(8, 52)),
        (true, 'Got it, thanks for the photos too.', _at(9, 12)),
      ]),
      _dm('priya', 'Priya Nair', [
        (false, 'Sharing the venue shortlist now', _at(8, 5)),
      ]),
      _dm('sofia', 'Sofia Reyes', const [], state: DmSessionState.pending),
      _dm('jonas', 'Jonas Weber', const [], state: DmSessionState.handshaking),
    ];

List<GroupSnapshot> chatsGroups() => [
      TestSnapshots.group(
          groupId: 'weekend',
          label: 'Weekend plans',
          deviceFingerprint: selfFp,
          memberCount: BigInt.from(4),
          messages: [
            TestMessages.group(
                fromDevice: 'Leo Park',
                fromFingerprint: 'leo',
                body: 'Saturday works for everyone.',
                sentAtMs: _at(9, 31)),
          ]),
      TestSnapshots.group(
          groupId: 'design',
          label: 'Design crew',
          deviceFingerprint: selfFp,
          memberCount: BigInt.from(6),
          messages: const []),
    ];

List<ChannelSnapshot> chatsChannels() => [
      TestSnapshots.channel(
          name: 'photography',
          deviceFingerprint: selfFp,
          displayName: me,
          messages: [
            TestMessages.channel(
                fromDevice: 'Nina Alvarez',
                fromFingerprint: 'nina',
                body: 'A few frames from the coast.',
                sentAtMs: _at(18, 20, daysAgo: 1)),
          ]),
      TestSnapshots.channel(
          name: 'city-cycling',
          topic: 'Group rides every Sunday',
          deviceFingerprint: selfFp,
          displayName: me,
          messages: const []),
    ];

/// The full chat list: five DMs, two groups, two channels.
ScriptableGateway chatsGateway() => ScriptableGateway()
  ..seedSessions(chatsDms())
  ..seedGroups(chatsGroups())
  ..seedChannels(chatsChannels());

/// A short chat list, so an organisation section below it stays in view.
ScriptableGateway shortGateway({List<GroupSnapshot> groups = const []}) =>
    ScriptableGateway()
      ..seedSessions([
        ...chatsDms().take(2),
        _dm('jonas', 'Jonas Weber', [
          (false, 'Thanks for the handover notes.', _at(8, 30, daysAgo: 2)),
        ]),
      ])
      ..seedGroups(groups);

/// Two invitations: a DM offer through a channel and one through a group.
ScriptableGateway invitationsGateway() {
  DmOffer offer(String id, String from, String fp) => DmOffer(
      offerId: id,
      fromDevice: from,
      fromFingerprint: fp,
      targetFingerprint: selfFp,
      inviteUri: 'mosh://invite?mesh=m&session=$id#fp=91A4-D2C8-77B0');
  final photography = chatsChannels().first;
  final weekend = chatsGroups().first;
  return ScriptableGateway()
    ..seedSessions(chatsDms().take(2))
    ..seedChannels([
      ChannelSnapshot(
          name: photography.name,
          topic: photography.topic,
          meshId: photography.meshId,
          displayName: photography.displayName,
          deviceFingerprint: selfFp,
          messages: photography.messages,
          attachments: const [],
          dmOffers: [offer('offer-nina', 'Nina Alvarez', 'nina')],
          mesh: null,
          events: const []),
    ])
    ..seedGroups([
      GroupSnapshot(
          groupId: weekend.groupId,
          meshId: weekend.meshId,
          label: weekend.label,
          displayName: me,
          deviceFingerprint: selfFp,
          creatorFingerprint: selfFp,
          isAdmin: true,
          state: 'ready',
          memberCount: weekend.memberCount,
          inviteUri: null,
          messages: weekend.messages,
          attachments: const [],
          dmOffers: [offer('offer-omar', 'Omar Haddad', 'omar')],
          mesh: null,
          events: const [],
          needsRejoin: false,
          orgPubkey: null,
          memberPeerIds: const [],
          typingMembers: const []),
    ]);
}

const orgKey = 'org-northwind';

const _members = [
  OrgMemberView(
      mossPeerId: 'peer-alex-7f3a92', name: me, role: 'admin', isSelf: true),
  OrgMemberView(
      mossPeerId: 'peer-maya-1c08de',
      name: 'Maya Chen',
      role: 'admin',
      isSelf: false),
  OrgMemberView(
      mossPeerId: 'peer-leo-5b71aa',
      name: 'Leo Park',
      role: 'member',
      isSelf: false),
  OrgMemberView(
      mossPeerId: 'peer-sofia-e42c19',
      name: 'Sofia Reyes',
      role: 'member',
      isSelf: false),
];

/// "Northwind Studio" with us as admin: roster, offers, new group form.
/// Jonas left the roster, so his DM carries the revoked badge.
OrgSnapshot northwind({bool offers = true}) => OrgSnapshot(
      orgPubkey: orgKey,
      orgName: 'Northwind Studio',
      meshId: 'northwind-mesh',
      ownPeerId: _members.first.mossPeerId,
      confirmationCode: '',
      inRoster: true,
      rosterVersion: BigInt.from(7),
      members: _members,
      dmOffers: offers
          ? const [
              OrgDmOfferView(
                  offerId: 'org-dm-1',
                  fromPeerId: 'peer-daniel-90bb21',
                  fromName: 'Daniel Kim',
                  inviteUri: 'mosh://invite?session=org-dm-1#fp=00'),
            ]
          : const [],
      groupOffers: offers
          ? const [
              OrgGroupOfferView(
                  offerId: 'org-group-1',
                  fromPeerId: 'peer-maya-1c08de',
                  fromName: 'Maya Chen',
                  groupLabel: 'Spring launch',
                  groupInviteUri: 'mosh://group?group=spring#fp=00'),
            ]
          : const [],
      dmLinks: const [
        OrgDmLink(peerId: 'peer-maya-1c08de', sessionId: 'maya'),
        OrgDmLink(peerId: 'peer-jonas-33d0f4', sessionId: 'jonas'),
      ],
    );

/// An organisation we joined that has not added us to its roster yet.
OrgSnapshot riverside() => const OrgSnapshot(
      orgPubkey: 'org-riverside',
      orgName: 'Riverside Makers',
      meshId: 'riverside-mesh',
      ownPeerId: 'peer-alex-7f3a92',
      confirmationCode: 'K7Q-42M-9TX',
      inRoster: false,
      members: [],
      dmOffers: [],
      groupOffers: [],
      dmLinks: [],
    );

/// The runtime with history persistence running, as in a real install.
NativeRuntimeStatus runtimeStatus() {
  final canned = cannedNativeRuntimeStatus();
  return NativeRuntimeStatus(
      moss: canned.moss,
      secureStorage: canned.secureStorage,
      persistence: const PersistenceRuntimeStatus(
          backend: 'redb+aes-256-gcm+os-keychain',
          database: 'mosh.redb',
          available: true,
          encryptedAtRest: true),
      openmlsSmoke: canned.openmlsSmoke,
      openmlsRoundtrip: canned.openmlsRoundtrip);
}

/// A Windows window controller over the test window channel.
Future<DesktopWindowController> windowsFrame() async {
  DesktopWindowPlatform().install();
  final window = (await DesktopWindowController.initialize(
      platform: TargetPlatform.windows))!;
  addTearDown(window.dispose);
  return window;
}

/// Mounts the real MoshApp at [size] on [location]. [script] seeds or
/// scripts the doubles before the first frame. [settle] false pumps a few
/// bounded frames for states that keep a spinner running.
Future<ScriptableBridge> mountChats(
  WidgetTester tester,
  Size size, {
  String location = AppRoutes.sessions,
  ScriptableGateway? gateway,
  void Function(ScriptableGateway gateway, ScriptableBridge bridge)? script,
  Map<String, int> unread = const {},
  bool collapsed = false,
  DesktopWindowController? window,
  bool settle = true,
}) async {
  final gw = gateway ?? chatsGateway();
  final bridge = ScriptableBridge(conversations: gw.conversations)
    ..seedNativeRuntimeStatus(runtimeStatus());
  script?.call(gw, bridge);
  figmaSurface(tester, size);
  appRouter.go(location);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gw),
      ...settingsAudioOverrides(),
      bridgeFacadeProvider.overrideWithValue(bridge),
      railLayoutStoreProvider.overrideWithValue(
          MemoryRailLayoutStore(RailLayout(collapsed: collapsed))),
      unreadLifecycleProvider.overrideWithBuild((ref, notifier) => unread),
      ...figmaLocale,
    ],
    child: MoshApp(windowController: window),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return bridge;
}

/// [matching] inside the chat list, which desktop mounts beside the chat.
Finder inRail(Finder matching) =>
    find.descendant(of: find.byType(SessionsScreen), matching: matching);

/// Types [query] into the chat list search.
Future<void> searchRail(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('chat-list-search')), query);
  await tester.pumpAndSettle();
  // Drop the caret so the frame shows the field at rest.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}
