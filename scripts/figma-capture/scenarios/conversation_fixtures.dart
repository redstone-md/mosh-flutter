// Seeded conversations for the conversation-area Figma scenes: a DM with
// Maya Chen, the "Weekend plans" group and the #photography channel, with
// realistic fictional content. Scenes in conversation_test.dart pick a
// variant and mount it through the real MoshApp shell.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mosh/main.dart' show MoshApp;
import 'package:mosh/src/state/gateway_provider.dart';
import '../../../test/support/settings.dart' show settingsAudioOverrides;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/rust/conversation/read_marks.dart';
import 'package:mosh/src/rust/conversation/recovery.dart';
import 'package:mosh/src/rust/message_deletion/origin.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime/wire_types.dart';

import '../../../test/features/routing/shell_harness.dart';
import '../../../test/support/message_builders.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'harness.dart';

part 'conversation_media.dart';
part 'conversation_rig.dart';
part 'conversation_rooms.dart';

final l10n = lookupAppLocalizations(const Locale('en'));

const me = 'Alex';
const meFp = 'a1f3c09e7b2d4e58';
const maya = 'Maya Chen';
const mayaFp = 'c4d2e81f09a7b3e6';
const leo = 'Leo Park';
const leoFp = '7e19b0c3d58a2f41';
const priya = 'Priya Nair';
const priyaFp = '5b80f2e4a1c97d36';

const dmId = 'maya';
const groupId = 'weekend';
const groupName = 'Weekend plans';

/// The org the group belongs to: only a group of an org comes with a roster.
const orgCoast = 'org-coast';
const channelName = 'photography';

/// Midnight today; scene times hang off it so the dividers read
/// "Yesterday" and "Today" on every run.
final DateTime _today = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}();

BigInt at({int daysAgo = 0, required int hour, int minute = 0}) =>
    BigInt.from(_today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: hour, minutes: minute))
        .millisecondsSinceEpoch);

/// A wide landscape: sky gradient, sun and two hill bands, as a PNG thumbnail.
String landscapePng({int w = 320, int h = 214, int seed = 0}) {
  final image = img.Image(width: w, height: h);
  final skyTop =
      [img.ColorRgb8(255, 176, 120), img.ColorRgb8(120, 170, 230)][seed % 2];
  final skyBottom =
      [img.ColorRgb8(255, 226, 178), img.ColorRgb8(206, 228, 246)][seed % 2];
  for (var y = 0; y < h; y++) {
    final t = y / h;
    for (var x = 0; x < w; x++) {
      final far = h * 0.62 + math.sin(x / w * 5 + seed) * h * 0.06;
      final near = h * 0.78 + math.sin(x / w * 3.2 + 1.7 + seed) * h * 0.07;
      final img.Color c;
      if (y > near) {
        c = img.ColorRgb8(46, 84, 62);
      } else if (y > far) {
        c = img.ColorRgb8(88, 128, 104);
      } else {
        c = img.ColorRgb8(
            (skyTop.r + (skyBottom.r - skyTop.r) * t).round(),
            (skyTop.g + (skyBottom.g - skyTop.g) * t).round(),
            (skyTop.b + (skyBottom.b - skyTop.b) * t).round());
      }
      image.setPixel(x, y, c);
    }
  }
  img.fillCircle(image,
      x: (w * 0.72).round(),
      y: (h * 0.36).round(),
      radius: (h * 0.11).round(),
      color: img.ColorRgb8(255, 246, 222));
  return base64Encode(img.encodePng(image));
}

/// 64 waveform buckets, base64 encoded, the way the recorder stores them.
String voicePeaks(int seed) => base64Encode(Uint8List.fromList([
      for (var i = 0; i < 64; i++)
        (60 +
                150 *
                    (0.5 + 0.5 * math.sin(i * 0.55 + seed)) *
                    (0.6 + 0.4 * math.cos(i * 0.21 + seed * 2)))
            .round()
            .clamp(20, 255),
    ]));

AttachmentDescriptor file(String id, String name, String mime, int size,
        {String? thumb, VoiceMeta? voice}) =>
    AttachmentDescriptor(
        attachmentId: id,
        contentHash: 'h-$id',
        fileName: name,
        mime: mime,
        totalSize: BigInt.from(size),
        thumbnailB64: thumb,
        voice: voice);

AttachmentView transfer(String id, AttachmentState state,
        {String direction = 'incoming',
        int done = 0,
        int chunks = 0,
        String? localPath}) =>
    AttachmentView(
        attachmentId: id,
        direction: direction,
        state: state,
        completedChunks: BigInt.from(done),
        chunkCount: BigInt.from(chunks),
        localPath: localPath);

ChatMessage dmMsg(String id, bool mine, String body, BigInt sent,
        {MessageDeliveryStatus? status,
        bool? read,
        AttachmentDescriptor? attachment,
        CallEvent? call,
        String? error,
        bool? retryable,
        DeletionMarker? deleted}) =>
    ChatMessage(
        // Own messages the peer has can be deleted for everyone.
        metadata: mine || deleted != null
            ? MessageMetadata(
                canDeleteForEveryone: mine, localOnly: false, deletion: deleted)
            : null,
        fromDevice: mine ? me : maya,
        body: body,
        messageId: id,
        sentAtMs: sent,
        attachment: attachment,
        callEvent: call,
        deliveryStatus:
            mine ? (status ?? MessageDeliveryStatus.delivered) : null,
        deliveryError: error,
        retryable: retryable,
        read: mine ? read : null);

/// The thread with one message deleted for everyone and one deletion still
/// on its way to the peer.
List<ChatMessage> dmThreadWithDeletions() => [
      for (final m in dmThread())
        switch (m.messageId) {
          'd6' => dmMsg('d6', false, '', m.sentAtMs!,
              deleted: const DeletionMarker(
                  scope: DeleteScope.forEveryone,
                  status: DeletionStatus.confirmed)),
          'd9' => dmMsg('d9', true, '', m.sentAtMs!,
              deleted: const DeletionMarker(
                  scope: DeleteScope.forEveryone,
                  status: DeletionStatus.pending)),
          _ => m,
        },
    ];

/// The DM thread: yesterday's plan and call, today's unread run and the
/// user's own replies in every delivery state.
List<ChatMessage> dmThread() => [
      dmMsg('d1', false, 'Are you still up for the coast trip this weekend?',
          at(daysAgo: 1, hour: 18, minute: 2)),
      dmMsg('d2', true, 'Yes! I was just looking at the tide tables.',
          at(daysAgo: 1, hour: 18, minute: 5),
          read: true),
      dmMsg('d3', true, 'Low tide is around 7 on Saturday, so an early start.',
          at(daysAgo: 1, hour: 18, minute: 5),
          read: true),
      dmMsg('d4', false, '', at(daysAgo: 1, hour: 18, minute: 20),
          call: CallEvent(
              kind: 'completed',
              durationMs: BigInt.from(754000),
              callId: 'c1')),
      dmMsg('d5', false, 'Leo can drive. He has room for three and the gear.',
          at(hour: 8, minute: 12)),
      dmMsg(
          'd6',
          false,
          'I booked the cabin near the lighthouse for two nights.',
          at(hour: 8, minute: 13)),
      dmMsg('d7', true, 'Perfect. I will bring the camera and the thermos.',
          at(hour: 8, minute: 30),
          read: true),
      dmMsg('d8', true, 'Should we leave at 6 to beat the traffic?',
          at(hour: 8, minute: 31),
          status: MessageDeliveryStatus.delivered),
      dmMsg('d9', true, 'Sending the packing list in a minute.',
          at(hour: 8, minute: 32),
          status: MessageDeliveryStatus.sent),
      dmMsg('d10', true, 'Also, do you have a spare headlamp?',
          at(hour: 8, minute: 33),
          status: MessageDeliveryStatus.queued),
      dmMsg('d11', true, 'Here is the route I mapped out.',
          at(hour: 8, minute: 34),
          status: MessageDeliveryStatus.failed,
          error: 'peer unreachable',
          retryable: true),
    ];

SessionSnapshot dmSession({
  List<ChatMessage>? messages,
  List<AttachmentView> attachments = const [],
  UnreadState? unread,
  DmSessionState state = DmSessionState.connected,
  PeerTransport transport = PeerTransport.direct,
  DmDeviceRevocationState? revocation,
  DmHistorySyncState? historySync,
  bool typing = false,
  DeletionSummary? deletion,
}) =>
    SessionSnapshot(
      deletionSummary: deletion,
      inviteAvailable: false,
      unread: unread,
      deviceRevocation: revocation,
      historySync: historySync,
      sessionId: dmId,
      meshId: 'mesh-coast',
      role: 'inviter',
      displayName: me,
      peerDisplayName: maya,
      state: state,
      transport: transport,
      peerMossId: '12D3KooWMaya9f2c',
      lastConnectOutcome: ConnectOutcome.requested,
      fingerprint: mayaFp,
      messages: messages ?? dmThread(),
      attachments: attachments,
      mesh: TestSnapshots.mesh(meshId: 'mesh-coast', peerCount: 4),
      events: const [],
      peerTypingUntilMs: typing
          ? BigInt.from(DateTime.now()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch)
          : null,
    );

/// The sidebar entries every scene shares, plus [dm]/[group]/[channel]
/// replacing the defaults.
ScriptableGateway seededGateway({
  SessionSnapshot? dm,
  GroupSnapshot? group,
  ChannelSnapshot? channel,
  List<SessionSnapshot> extraSessions = const [],
}) =>
    ScriptableGateway()
      ..seedSessions([
        dm ?? dmSession(),
        ...extraSessions,
        TestSnapshots.dm(
            sessionId: 'leo',
            displayName: me,
            peerDisplayName: leo,
            messages: [
              TestMessages.dm(
                  fromDevice: leo,
                  body: 'Thanks for the photos!',
                  sentAtMs: at(daysAgo: 1, hour: 21)),
            ]),
      ])
      ..seedGroups([group ?? groupSnapshot()])
      ..seedChannels([channel ?? channelSnapshot()]);

/// A call module that starts nothing, so a conversation draws the controls
/// of its calls as it does in the app: the handset of a call entry is lit.
final Override figmaCalls = conversationCallBindingProvider.overrideWithValue(
    ConversationCallBinding(
        start: (ref, id) async => null,
        overlay: (context, host) => const SizedBox.shrink()));

/// Mounts the real shell on [location] with [gateway].
Future<ScriptableBridge> openShell(WidgetTester tester, Size size,
    {required ScriptableGateway gateway,
    String location = '',
    List<Override> overrides = const []}) async {
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  await pumpShellApp(tester,
      gateway: gateway,
      bridge: bridge,
      physical: size,
      location: location.isEmpty ? AppRoutes.dmFor(dmId) : location,
      overrides: [...figmaLocale, figmaCalls, ...overrides]);
  return bridge;
}

/// The message [text] in the open thread, not its copy in the details panel.
Finder inThread(String text) => find.descendant(
    of: find.byType(ConversationMessageListView), matching: find.text(text));

bool isDesktop(Size size) => size.width >= 1000;

/// Right-clicks the message [body] and waits for the context menu.
Future<void> openMessageMenu(WidgetTester tester, String body) async {
  await tester.tap(inThread(body).first,
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

/// A conversation scene whose images have finished decoding before export.
FigmaScene scene(String id, String title,
        Future<void> Function(WidgetTester tester, Size size) pump,
        {List<FigmaDevice> devices = FigmaDevice.values}) =>
    FigmaScene(id, title, (tester, size) async {
      // A file image loading in an earlier scene must not leak into this one.
      imageCache
        ..clear()
        ..clearLiveImages();
      await pump(tester, size);
      await settleImages(tester);
    }, devices: devices);
