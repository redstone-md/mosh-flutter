import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_checkout.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/plus/plus_settings_card.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:mosh/src/features/device_link/qr_image.dart';

import '../../support/pump.dart';
import '../../support/plus/fakes.dart';

void main() {
  testWidgets('checkout persists QR, resumes issuance and opts in explicitly',
      (tester) async {
    final native = MemoryPlusCommands();
    final billing = TestBilling();
    final container = ProviderContainer(overrides: [
      plusConfigProvider.overrideWithValue(testPlusConfig),
      plusCommandsProvider.overrideWithValue(native),
      plusBillingProvider.overrideWithValue(billing),
      plusPollIntervalProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(
        tester,
        const Scaffold(
            body: SingleChildScrollView(
                child: RepaintBoundary(
                    key: ValueKey('checkout-qr'), child: PlusSettingsCard()))),
        container: container);
    expect(find.textContaining('Devnet'), findsWidgets);
    expect(find.textContaining('1.000000001'), findsOneWidget);
    await tester.tap(find.text('Create payment QR'));
    await tester.pumpAndSettle();
    expect(native.current.order?.id, 'test-order');
    expect(find.byType(QrImageView), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('checkout-qr')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(await decodeDeviceQr(bytes!.buffer.asUint8List()),
          testOrder['payment_uri']);
      image.dispose();
    });
    expect(find.byType(Switch), findsNothing);

    billing.paid = true;
    billing.failIssue = true;
    await container.read(plusProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(native.preparations, 1);
    expect(find.text('Could not update Mosh+. Retry.'), findsOneWidget);
    billing.failIssue = false;
    await container.read(plusProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(billing.requests,
        ['durable-blinded-request', 'durable-blinded-request']);
    expect(native.current.active, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(native.current.order?.status, PlusPaymentStatus.issued);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(native.current.visible, isTrue);
  });

  testWidgets('Russian checkout fits a narrow window with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final native = MemoryPlusCommands();
    final billing = TestBilling();
    final container = ProviderContainer(overrides: [
      plusConfigProvider.overrideWithValue(testPlusConfig),
      plusCommandsProvider.overrideWithValue(native),
      plusBillingProvider.overrideWithValue(billing),
      plusPollIntervalProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(
        tester,
        Builder(
            builder: (context) => Localizations.override(
                context: context,
                locale: const Locale('ru'),
                child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: const Scaffold(
                        body: SingleChildScrollView(
                            child: PlusSettingsCard()))))),
        container: container);
    await container.read(plusProvider.notifier).purchase();
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone hands the pending payment to a wallet app or copies it',
      (tester) async {
    final opened = <Uri>[];
    var walletAnswers = true;
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final container = ProviderContainer(overrides: [
      plusConfigProvider.overrideWithValue(testPlusConfig),
      plusCommandsProvider.overrideWithValue(MemoryPlusCommands()),
      plusBillingProvider.overrideWithValue(TestBilling()),
      plusPollIntervalProvider.overrideWithValue(null),
      plusWalletOpenerProvider.overrideWithValue((payment) async {
        opened.add(payment);
        return walletAnswers;
      }),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(tester,
        const Scaffold(body: SingleChildScrollView(child: PlusSettingsCard())),
        container: container);
    await container.read(plusProvider.notifier).purchase();
    await tester.pumpAndSettle();
    final payment = testOrder['payment_uri'] as String;

    await tester.tap(find.text('Open in wallet'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(payment)]);
    expect(find.textContaining('No wallet app'), findsNothing);

    walletAnswers = false;
    await tester.tap(find.text('Open in wallet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No wallet app'), findsOneWidget);

    await tester.tap(find.text('Copy payment link'));
    await tester.pumpAndSettle();
    expect(copied, [payment]);
  });
}
