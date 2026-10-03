// Renders the shipping Flutter UI with fictional conversations, without Rust.
// flutter test scripts/capture_readme.dart --dart-define=SETUP_PREVIEW=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../test/features/routing/shell_harness.dart';
import '../test/support/first_run_preview.dart';
import '../test/support/message_builders.dart';
import '../test/support/scriptable_gateway.dart';

final _time = DateTime(2026, 10, 3, 9, 41);

AttachmentDescriptor _attachment({bool voice = false}) => AttachmentDescriptor(
      attachmentId: voice ? 'weekend-voice' : 'weekend-route',
      contentHash: 'readme-sample',
      fileName: voice ? 'voice.m4a' : 'Riverside walk.pdf',
      mime: voice ? 'audio/mp4' : 'application/pdf',
      totalSize: BigInt.from(voice ? 18000 : 24576),
      voice: voice
          ? VoiceMeta(
              durationMs: 8200,
              peaksB64: base64Encode(Uint8List.fromList(
                  List.generate(64, (i) => 28 + (i * 37) % 185))))
          : null,
    );

SessionSnapshot _mayaChat() {
  final conversation = [
    ('Maya Chen', 'Coffee after the walk?'),
    ('Alex', 'Absolutely. Riverside at 10?'),
    ('Maya Chen', 'Perfect. The weather looks good for once.'),
    ('Alex', 'I found a quieter route along the river.'),
    ('Alex', ''),
    ('Maya Chen', 'That looks lovely. Let\'s take the long way back.'),
    ('Maya Chen', ''),
    ('Alex', 'Deal. I\'ll bring the camera.'),
    ('Maya Chen', 'See you by the bridge!'),
  ];
  return TestSnapshots.dm(
      sessionId: 'maya',
      displayName: 'Alex',
      peerDisplayName: 'Maya Chen',
      messages: [
        for (final (index, (author, body)) in conversation.indexed)
          TestMessages.dm(
              fromDevice: author,
              body: body,
              messageId: 'weekend-$index',
              sentAtMs: BigInt.from(
                  _time.add(Duration(minutes: index)).millisecondsSinceEpoch),
              attachment: index == 4
                  ? _attachment()
                  : index == 6
                      ? _attachment(voice: true)
                      : null,
              deliveryStatus: MessageDeliveryStatus.sent,
              read: author == 'Alex'),
      ]);
}

ScriptableGateway _gateway() => ScriptableGateway()
  ..seedSessions([
    _mayaChat(),
    TestSnapshots.dm(sessionId: 'leo', peerDisplayName: 'Leo Park', messages: [
      TestMessages.dm(fromDevice: 'Leo Park', body: 'Thanks for the photos!')
    ]),
  ])
  ..seedGroups([
    TestSnapshots.group(
        groupId: 'weekend',
        label: 'Weekend plans',
        deviceFingerprint: 'self',
        messages: [
          TestMessages.group(
              fromDevice: 'Nora',
              fromFingerprint: 'nora',
              body: 'Saturday works for everyone.')
        ]),
  ])
  ..seedChannels([
    TestSnapshots.channel(
        name: 'photography',
        deviceFingerprint: 'self',
        messages: [
          TestMessages.channel(
              fromDevice: 'Leo Park',
              fromFingerprint: 'leo',
              body: 'A few frames from the coast.')
        ]),
  ]);

Future<void> _save(WidgetTester tester) async {
  final boundary = tester
      .firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/assets/chat-desktop.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  testWidgets('capture the desktop UI with fictional chat data',
      (tester) async {
    const recorder = MethodChannel('com.llfbandit.record/messages');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(recorder, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(recorder, null));
    await prepareSetupPreview(tester);
    await pumpShellApp(tester,
        gateway: _gateway(), physical: const Size(1440, 900));
    await tester.tap(find.descendant(
        of: find.byType(SessionsScreen), matching: find.text('Maya Chen')));
    await tester.pumpAndSettle();
    expect(find.text('Coffee after the walk?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
