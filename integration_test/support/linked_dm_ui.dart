import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';

import '../../test/support/pump.dart';

/// Real screens and gateways, with the same conversation timer as the app root.
final class LinkedDmUi {
  LinkedDmUi(this.tester, this.session);

  final WidgetTester tester;
  final String session;

  Finder get input => find.descendant(
      of: find.byType(ConversationComposer), matching: find.byType(TextField));

  Future<void> devices() => pumpScreen(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: DevicesSettingsSection())),
      overrides: [
        autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
      ],
      settle: false);

  Future<void> open() => pumpScreen(tester, Consumer(builder: (_, ref, __) {
        ref.watch(autoPollProvider);
        return DmScreen(sessionId: session);
      }), overrides: [
        autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
      ], settle: false);

  Future<void> send(String body) async {
    await visible(input);
    await eventually(
        () async => tester.widget<TextField>(input).enabled != false);
    await tester.enterText(input, body);
    await tap(find.byKey(kComposerSendButtonKey));
    await eventually(
        () async => tester.widget<TextField>(input).controller!.text.isEmpty);
    await visible(find.text(body));
  }

  Future<void> visible(Finder finder) =>
      eventually(() async => finder.evaluate().isNotEmpty);

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> eventually(Future<bool> Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      final done = await ready();
      final error = tester.takeException();
      if (error != null) throw error;
      if (done) return;
      expect(DateTime.now().isBefore(deadline), isTrue,
          reason:
              'The linked DM stage must finish with real native dependencies');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
  }
}
