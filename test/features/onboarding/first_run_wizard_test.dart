import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_wizard.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/scriptable_device_link.dart';

void main() {
  testWidgets('name is required and first-device setup completes end to end',
      (tester) async {
    final harness = FirstRunHarness();
    await harness.pump(tester);
    expect(find.byType(SessionsScreen), findsNothing);
    await tapSetup(tester, 'Continue');
    expect(find.text('Enter a name to continue.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  Juno  ');
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.displayName, 'Juno');
    expect(harness.store.profile!.step, SetupStep.device);
    await tapSetup(tester, 'This is my first device');
    expect(harness.store.profile!.step, SetupStep.network);
    await tapSetup(tester, 'Save and finish');
    expect(harness.store.profile!.completed, isTrue);
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('interrupted setup restores the step and supports going back',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    await harness.pump(tester);
    await tapSetup(tester, 'Back');
    expect(find.widgetWithText(TextFormField, 'Juno'), findsOneWidget);
    await tapSetup(tester, 'Continue');
    await tapSetup(tester, 'This is my first device');
    await tapSetup(tester, 'Back');
    expect(harness.store.profile!.step, SetupStep.device);
  });

  testWidgets('completed installation opens chats without the wizard',
      (tester) async {
    final harness = FirstRunHarness(
        profile: const FirstRunProfile(displayName: 'Juno', completed: true));
    await harness.pump(tester);
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('QR link import displays proof and can cancel before approval',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    await harness.pump(tester);
    await tapSetup(tester, 'Connect to an existing profile');
    await tester.enterText(
        find.byType(TextField), 'mosh://device-link/example');
    await tester.ensureVisible(find.byIcon(Icons.arrow_forward));
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(harness.link.imported, ['mosh://device-link/example']);
    expect(find.text('ABCDEF123456'), findsOneWidget);
    await tapSetup(tester, 'Cancel linking and continue independently');
    expect(harness.link.cancellations, 1);
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('device snapshot failure offers retry before choosing a device',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device),
        link: ScriptableDeviceLink()..buildError = StateError('snapshot'));
    await harness.pump(tester);
    expect(find.text('Retry'), findsOneWidget);
    expect(harness.store.profile!.step, SetupStep.device);
    harness.link.buildError = null;
    await tapSetup(tester, 'Retry');
    await tapSetup(tester, 'This is my first device');
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('committed delivery disables cancellation and continuing',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device),
        link: ScriptableDeviceLink(
            snapshot: setupDeviceSnapshot(
                role: DeviceLinkRole.joining,
                phase: DeviceLinkPhase.delivering)));
    await harness.pump(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(find.widgetWithText(
        OutlinedButton, 'Cancel linking and continue independently'));
    expect(button.onPressed, isNull);
    expect(harness.link.cancellations, 0);
    harness.link.publish(setupDeviceSnapshot(
        phase: DeviceLinkPhase.linked, canJoin: false, devices: 2));
    await tester.pumpAndSettle();
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('failed saving keeps the name form and offers retry',
      (tester) async {
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester);
    harness.store.writeError = StateError('disk');
    await tester.enterText(find.byType(TextFormField), 'Juno');
    await tapSetup(tester, 'Continue');
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(harness.store.profile!.step, SetupStep.name);
    harness.store.writeError = null;
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.step, SetupStep.device);
  });

  testWidgets('approval racing cancellation preserves the linked profile',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device),
        link: ScriptableDeviceLink(
            snapshot: setupDeviceSnapshot(
                role: DeviceLinkRole.joining,
                phase: DeviceLinkPhase.awaitingConfirmation)));
    await harness.pump(tester);
    harness.link.snapshotAfterCancel = setupDeviceSnapshot(
        phase: DeviceLinkPhase.failed, canJoin: false, devices: 2);
    await tapSetup(tester, 'Cancel linking and continue independently');
    expect(harness.store.profile!.step, SetupStep.device);
    expect(
        find.textContaining('Linking was already approved.'), findsOneWidget);
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('failed cancellation keeps the pairing proof and can retry',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device),
        link: ScriptableDeviceLink(
            snapshot: setupDeviceSnapshot(
                role: DeviceLinkRole.joining,
                phase: DeviceLinkPhase.awaitingConfirmation)));
    await harness.pump(tester);
    harness.link.actionError = StateError('cancel');
    await tapSetup(tester, 'Cancel linking and continue independently');
    expect(harness.store.profile!.step, SetupStep.device);
    expect(find.text('ABCDEF123456'), findsOneWidget);
    expect(find.textContaining('Could not finish the device step'),
        findsOneWidget);
    harness.link.actionError = null;
    await tapSetup(tester, 'Cancel linking and continue independently');
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('unreadable preferences block chats until a successful retry',
      (tester) async {
    final harness = FirstRunHarness(profile: const FirstRunProfile())
      ..store.readError = const FormatException('corrupt');
    await harness.pump(tester);
    expect(find.byType(SessionsScreen), findsNothing);
    expect(find.textContaining('Could not read your setup'), findsOneWidget);
    harness.store.readError = null;
    await tapSetup(tester, 'Retry');
    expect(find.byType(FirstRunWizard), findsOneWidget);
  });

  testWidgets('an incoming invitation waits until setup has completed',
      (tester) async {
    resetMoshDeepLinkIntakeStateForTest();
    final stream = StreamController<Uri>();
    final intake = startMoshDeepLinkIntake(linkStream: stream.stream);
    addTearDown(() async {
      intake.dispose();
      await stream.close();
      resetMoshDeepLinkIntakeStateForTest();
    });
    final harness = FirstRunHarness(
        profile: const FirstRunProfile(
            displayName: 'Juno', step: SetupStep.network));
    await harness.pump(tester);
    const invitation = 'mosh://invite?peer=test&port=1234#fp=abc';
    stream.add(Uri.parse(invitation));
    await tester.pumpAndSettle();
    expect(find.byType(InvitePasteScreen), findsNothing);
    await tapSetup(tester, 'Save and finish');
    expect(find.byType(InvitePasteScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, invitation), findsOneWidget);
  });

  for (final size in [const Size(1200, 850), const Size(390, 844)]) {
    for (final step in SetupStep.values) {
      testWidgets('$step fits $size with enlarged Russian text',
          (tester) async {
        final harness = FirstRunHarness(
            profile: FirstRunProfile(displayName: 'Юна', step: step));
        await harness.pump(tester, size: size, scale: 2);
        harness.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('ru'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = switch (step) {
          SetupStep.name => 'Продолжить',
          SetupStep.device => 'Это моё первое устройство',
          SetupStep.network => 'Сохранить и завершить',
        };
        await tester.ensureVisible(find.text(action));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('desktop places the illustration beside the name form',
      (tester) async {
    if (const bool.fromEnvironment('SETUP_PREVIEW')) {
      await tester.runAsync(_loadPreviewFonts);
    }
    await FirstRunHarness(profile: const FirstRunProfile()).pump(tester);
    if (const bool.fromEnvironment('SETUP_PREVIEW')) {
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/onboarding/welcome.png'),
          tester.element(find.byType(FirstRunWizard))));
      await tester.pump();
    }
    final illustration = tester.getRect(find.byType(Image));
    final name = tester.getRect(find.byType(TextFormField));
    expect(illustration.right, lessThan(name.left));
    if (!const bool.fromEnvironment('SETUP_PREVIEW')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('setup-preview')));
    await tester.runAsync(() async {
      final picture = await boundary.toImage();
      final png = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      await Directory('build').create();
      await File('build/first-run-preview.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });
  });
}

Future<void> _loadPreviewFonts() async {
  const fonts = {
    'Inter Tight': String.fromEnvironment('SETUP_FONT'),
    'MaterialIcons': String.fromEnvironment('SETUP_ICONS'),
  };
  for (final entry in fonts.entries) {
    if (entry.value.isEmpty) continue;
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
    await loader.load();
  }
}
