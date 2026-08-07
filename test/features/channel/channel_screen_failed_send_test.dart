// Widget tests for the Gap-1 failed-send retry queue in the CHANNEL screen
// (lib/src/features/channel/channel_screen.dart): a text send that THROWS
// records `_lastFailedSend` + `_chatError` (the inline ChatError banner
// appears with a Retry button) and LEAVES the composer text intact; a
// successful retry clears both + the composer. 1-1 with React
// `use-chat-orchestration.ts` L85-149. Mirrors the DM suite
// (dm_screen_failed_send_test.dart) on the channel send seam.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

ChannelSnapshot _snapshot({required String name}) => ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'testmesh',
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

/// A FakeGateway subclass whose `sendChannel` throws on the first call and
/// succeeds on the second, recording each body. Mirrors the DM suite's
/// `_RecordingGateway`.
class _RecordingGateway extends FakeGateway {
  final List<String> bodies = [];
  int _throwsLeft;

  _RecordingGateway({int throwsLeft = 1}) : _throwsLeft = throwsLeft;

  @override
  Future<ChannelSendResult> sendChannel(
      {required String name, required String body}) {
    bodies.add(body);
    if (_throwsLeft > 0) {
      _throwsLeft--;
      return Future.error(Exception('send boom'));
    }
    return Future.value(ChannelSendResult(
      name: name,
      bytes: BigInt.from(body.codeUnits.length),
      messageId: 'msg-1',
      sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
    ));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _RecordingGateway gateway, {
  required String name,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      channelSnapshotProvider(name)
          .overrideWith((ref) async => _snapshot(name: name)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChannelScreen(name: name),
    ),
  ));
  await tester.pumpAndSettle();
}

// The composer's TextField, scoped under [ConversationComposer] so it does
// not collide with ConversationTools' search TextField (also a TextField).
Finder _composerField() => find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    );

void main() {
  const name = 'chan-failed-send';

  testWidgets(
      'a thrown text send records the failure + banner + keeps the composer body',
      (tester) async {
    final gateway = _RecordingGateway(throwsLeft: 1);
    await _pump(tester, gateway, name: name);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    expect(gateway.bodies, ['hello there']);
    expect(find.textContaining('send boom'), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(ChannelScreen)))!;
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    // The composer body is PRESERVED on failure.
    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, 'hello there');
  });

  testWidgets('a successful retry clears the failure + banner + composer',
      (tester) async {
    final gateway = _RecordingGateway(throwsLeft: 1);
    await _pump(tester, gateway, name: name);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(tester.element(find.byType(ChannelScreen)))!;
    expect(find.textContaining('send boom'), findsOneWidget);
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    await tester.tap(find.text(l.chatErrorRetry));
    await tester.pumpAndSettle();

    expect(gateway.bodies, ['hello there', 'hello there']);
    expect(find.textContaining('send boom'), findsNothing);
    expect(find.text(l.chatErrorRetry), findsNothing);

    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, '');
  });
}
