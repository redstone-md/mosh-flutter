import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/plus/plus_settings_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:mosh/src/features/device_link/qr_image.dart';
import '../../support/plus/mainnet_fakes.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'an active subscriber can renew in CLXAI without losing the current badge setting',
      (tester) async {
    final native = MainnetTestCommands();
    await screen(tester, native);
    expect(find.textContaining('Devnet'), findsNothing);
    await tester.tap(find.text('CLXAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 30 days'));
    await tester.pumpAndSettle();
    expect(native.selectedAsset, 'CLXAI');
    expect(await readQr(tester), mainnetOrder['payment_uri']);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets(
      'wallet recovery shows its pairing code and a public QR without the polling capability',
      (tester) async {
    final native = MainnetTestCommands();
    await screen(tester, native);
    await tester.ensureVisible(find.text('Recover purchase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recover purchase'));
    await tester.pumpAndSettle();
    expect(find.text('ABCDEF12'), findsOneWidget);
    expect(await readQr(tester), 'https://billing.example/recover/session');
    expect(find.textContaining('private-poll-token'), findsNothing);
  });
}

Future<void> screen(WidgetTester tester, MainnetTestCommands native) async {
  final container = ProviderContainer(overrides: [
    plusConfigProvider.overrideWithValue(mainnetConfig),
    plusCommandsProvider.overrideWithValue(native),
    plusBillingProvider.overrideWithValue(MainnetTestBilling()),
    plusPollIntervalProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);
  await pumpScreen(
      tester,
      const Scaffold(
          body: SingleChildScrollView(
              child: RepaintBoundary(
                  key: ValueKey('mainnet-card'), child: PlusSettingsCard()))),
      container: container);
}

Future<String?> readQr(WidgetTester tester) async {
  expect(find.byType(QrImageView), findsOneWidget);
  await tester.ensureVisible(find.byType(QrImageView));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('mainnet-card')));
  return tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final decoded = await decodeDeviceQr(bytes!.buffer.asUint8List());
    image.dispose();
    return decoded;
  });
}
