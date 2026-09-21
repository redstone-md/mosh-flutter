// The table a conversation test runs over: the DM, the channel and the
// group, each with the screen to mount, the route to push, and the provider
// override that feeds it a snapshot.
//
// Write a conversation test once and loop over [conversationCases]. Anything
// one kind alone does -- calls, the rejoin banner, the org prompt -- stays in
// that kind's own test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/shared/attachment_launcher.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import 'pump.dart';
import 'scriptable_gateway.dart';

/// The local device in every case, so a test can say "my own message".
const String ownDevice = 'me';
const String ownFingerprint = 'fp-me';

/// One message, written once and turned into whichever generated type the
/// kind needs. The defaults make a message from someone else.
class TestMessage {
  const TestMessage({
    this.fromDevice = 'peer',
    this.fromFingerprint = 'fp-peer',
    this.body = '',
    this.messageId,
    this.sentAtMs,
    this.attachment,
    this.callEvent,
    this.deliveryStatus,
    this.deliveryError,
    this.retryable,
  });

  /// A message the local device sent.
  const TestMessage.own({
    String body = '',
    String? messageId,
    BigInt? sentAtMs,
    AttachmentDescriptor? attachment,
    MessageDeliveryStatus? deliveryStatus,
    String? deliveryError,
    bool? retryable,
  }) : this(
          fromDevice: ownDevice,
          fromFingerprint: ownFingerprint,
          body: body,
          messageId: messageId,
          sentAtMs: sentAtMs,
          attachment: attachment,
          deliveryStatus: deliveryStatus,
          deliveryError: deliveryError,
          retryable: retryable,
        );

  final String fromDevice;
  final String fromFingerprint;
  final String body;
  final String? messageId;
  final BigInt? sentAtMs;
  final AttachmentDescriptor? attachment;

  /// A call that started, ended or was missed. Only a DM carries one; the
  /// channel and group message types have no such field.
  final CallEvent? callEvent;

  final MessageDeliveryStatus? deliveryStatus;
  final String? deliveryError;
  final bool? retryable;

  ChatMessage toDm() => ChatMessage(
        fromDevice: fromDevice,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        callEvent: callEvent,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
      );

  ChannelMessage toChannel() => ChannelMessage(
        fromDevice: fromDevice,
        fromFingerprint: fromFingerprint,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
      );

  GroupMessage toGroup() => GroupMessage(
        fromDevice: fromDevice,
        fromFingerprint: fromFingerprint,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
      );
}

/// One conversation kind, ready to mount.
class ConversationCase {
  const ConversationCase({
    required this.label,
    required this.target,
    required this.screen,
    required this.route,
    required this.leaveIcon,
    required this.leaveTitle,
    required this.leaveConfirmLabel,
    required this.snapshotOverride,
  });

  /// How the kind reads in a test name.
  final String label;

  final AnyConversationTarget target;

  /// The screen to mount directly.
  final Widget screen;

  /// Where to send the router when the test needs real navigation.
  final String route;

  /// The header button that starts leaving this conversation.
  final IconData leaveIcon;

  /// The confirm dialog's title and its confirm button, for the fixture
  /// [snapshotOverride] builds.
  final String leaveTitle;
  final String leaveConfirmLabel;

  /// Feeds the screen a snapshot with these messages and transfers.
  final Override Function({
    List<TestMessage> messages,
    List<AttachmentView> attachments,
  }) snapshotOverride;
}

/// The three kinds every shared conversation test runs over.
List<ConversationCase> conversationCases({
  String dmId = 'sess-under-test',
  String channelName = 'chan-under-test',
  String groupId = 'group-under-test',
}) =>
    [
      ConversationCase(
        label: 'DM',
        target: DmTarget(dmId),
        screen: DmScreen(sessionId: dmId),
        route: AppRoutes.dmFor(dmId),
        leaveIcon: Icons.close,
        leaveTitle: 'Delete chat with peer?',
        leaveConfirmLabel: 'Delete chat',
        snapshotOverride: ({
          List<TestMessage> messages = const [],
          List<AttachmentView> attachments = const [],
        }) =>
            activeSessionProvider(dmId).overrideWith(
          (ref) async => SessionSnapshot(
            sessionId: dmId,
            meshId: 'testmesh',
            role: 'inviter',
            displayName: ownDevice,
            peerDisplayName: 'peer',
            state: DmSessionState.connected,
            transport: PeerTransport.direct,
            fingerprint: ownFingerprint,
            messages: messages.map((m) => m.toDm()).toList(),
            attachments: attachments,
            events: const [],
          ),
        ),
      ),
      ConversationCase(
        label: 'channel',
        target: ChannelTarget(channelName),
        screen: ChannelScreen(name: channelName),
        route: AppRoutes.channelFor(channelName),
        leaveIcon: Icons.logout,
        leaveTitle: 'Leave #$channelName?',
        leaveConfirmLabel: 'Leave channel',
        snapshotOverride: ({
          List<TestMessage> messages = const [],
          List<AttachmentView> attachments = const [],
        }) =>
            channelSnapshotProvider(channelName).overrideWith(
          (ref) async => ChannelSnapshot(
            name: channelName,
            topic: '',
            meshId: 'testmesh',
            displayName: ownDevice,
            deviceFingerprint: ownFingerprint,
            messages: messages.map((m) => m.toChannel()).toList(),
            attachments: attachments,
            dmOffers: const [],
            events: const [],
          ),
        ),
      ),
      ConversationCase(
        label: 'group',
        target: GroupTarget(groupId),
        screen: GroupScreen(groupId: groupId),
        route: AppRoutes.groupFor(groupId),
        leaveIcon: Icons.logout,
        leaveTitle: 'Leave Squad?',
        leaveConfirmLabel: 'Leave group',
        snapshotOverride: ({
          List<TestMessage> messages = const [],
          List<AttachmentView> attachments = const [],
        }) =>
            groupSnapshotProvider(groupId).overrideWith(
          (ref) async => GroupSnapshot(
            groupId: groupId,
            meshId: 'testmesh',
            label: 'Squad',
            displayName: ownDevice,
            deviceFingerprint: ownFingerprint,
            creatorFingerprint: ownFingerprint,
            isAdmin: false,
            state: 'ready',
            memberCount: BigInt.from(2),
            messages: messages.map((m) => m.toGroup()).toList(),
            attachments: attachments,
            dmOffers: const [],
            events: const [],
            needsRejoin: false,
            memberPeerIds: const [],
            typingMembers: const [],
          ),
        ),
      ),
    ];

/// Mounts [testCase]'s screen with a snapshot built from [messages] and
/// [attachments].
///
/// Pass [useRouter] when the test needs the screen to navigate for real;
/// otherwise the screen is mounted on its own, which is faster.
Future<void> pumpConversation(
  WidgetTester tester,
  ConversationCase testCase, {
  ScriptableGateway? gateway,
  List<TestMessage> messages = const [],
  List<AttachmentView> attachments = const [],
  AttachmentLauncher? launcher,
  bool useRouter = false,
}) async {
  final overrides = <Override>[
    if (gateway != null) gatewayProvider.overrideWithValue(gateway),
    if (launcher != null)
      attachmentLauncherProvider.overrideWithValue(launcher),
    testCase.snapshotOverride(messages: messages, attachments: attachments),
  ];
  if (useRouter) {
    await pumpRoute(tester, testCase.route, overrides: overrides);
  } else {
    await pumpScreen(tester, testCase.screen, overrides: overrides);
  }
}

/// A file on a message.
AttachmentDescriptor testAttachment({
  required String attachmentId,
  String fileName = 'report.pdf',
  String mime = 'application/pdf',
  int totalSize = 1536,
}) =>
    AttachmentDescriptor(
      attachmentId: attachmentId,
      contentHash: 'h-$attachmentId',
      fileName: fileName,
      mime: mime,
      totalSize: BigInt.from(totalSize),
    );

/// That file's transfer state.
AttachmentView testAttachmentView({
  required String attachmentId,
  required AttachmentState state,
  String direction = 'incoming',
  int completedChunks = 0,
  int chunkCount = 0,
  String? localPath,
}) =>
    AttachmentView(
      attachmentId: attachmentId,
      direction: direction,
      state: state,
      completedChunks: BigInt.from(completedChunks),
      chunkCount: BigInt.from(chunkCount),
      localPath: localPath,
    );
