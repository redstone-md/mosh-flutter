// Widget tests for Gap 5 in the CHANNEL screen
// (lib/src/features/channel/channel_screen.dart): the composer-clear-on-success
// is CONDITIONAL on the composer still holding the sent body (1-1 with React
// use-chat-orchestration.ts L120-125 `setComposer(c => c.trim() === body ? ""
// : c)`). On a successful send the composer is cleared ONLY when it still
// equals `body`; if the user typed MORE text while the send was in flight,
// the new text survives (the composer is NOT clobbered). Mirrors the
// recording-fake idiom in channel_screen_failed_send_test.dart, but the fake
// `sendChannel` returns a `Completer`-backed future so the test controls
// WHEN the send resolves and can mutate the composer mid-flight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
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

Future<void> _pump(
  WidgetTester tester,
  ScriptableGateway gateway, {
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

TextEditingController _controllerOf(WidgetTester tester) =>
    tester.widget<TextField>(_composerField()).controller!;

void main() {
  const name = 'chan-conditional-clear';

  testWidgets(
      'a successful send clears the composer when it still equals the body',
      (tester) async {
    final gateway = ScriptableGateway()..hold(GatewayMethod.sendChannel);
    await _pump(tester, gateway, name: name);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    // Do NOT settle: the send is in flight (completer unresolved).
    await tester.pump();

    expect(gateway.argValues<String>(GatewayMethod.sendChannel, 'body'), ['hello there']);
    expect(_controllerOf(tester).text, 'hello there');

    // The composer still equals the sent body, so resolving the send clears
    // it (the common case).
    gateway.release(GatewayMethod.sendChannel);
    await tester.pumpAndSettle();

    expect(_controllerOf(tester).text, '');
  });

  testWidgets(
      'a successful send does NOT clear the composer if the user typed more',
      (tester) async {
    final gateway = ScriptableGateway()..hold(GatewayMethod.sendChannel);
    await _pump(tester, gateway, name: name);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    // Do NOT settle: the send is in flight (completer unresolved).
    await tester.pump();

    expect(gateway.argValues<String>(GatewayMethod.sendChannel, 'body'), ['hello there']);

    // Simulate the user typing MORE text while the send is in flight by
    // writing directly to the composer controller (the TextField is
    // disabled while `_sending` is true, so `enterText` would be a no-op;
    // React's composer is a plain controlled input that stays editable
    // during the in-flight send, so we mutate the controller directly to
    // mirror the parity scenario). This does not resolve the completer.
    _controllerOf(tester).text = 'hello there and more';
    await tester.pump();
    expect(_controllerOf(tester).text, 'hello there and more');

    // Resolve the in-flight send. The composer no longer equals the sent
    // body, so the conditional clear leaves the new text intact (1-1 with
    // React: in-flight typing survives).
    gateway.release(GatewayMethod.sendChannel);
    await tester.pumpAndSettle();

    expect(_controllerOf(tester).text, 'hello there and more');
  });
}
