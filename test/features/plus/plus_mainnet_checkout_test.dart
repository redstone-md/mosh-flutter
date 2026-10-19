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
import 'package:mosh/src/rust/plus/recovery_types.dart';

void main() {
  testWidgets(
      'paused sales disable new payment QR while keeping recovery available',
      (tester) async {
    final native = MainnetTestCommands();
    await screen(tester, native, salesEnabled: false);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        find.text('Purchases are unavailable in this build.'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Recover purchase'))
            .onPressed,
        isNotNull);
  });
  testWidgets(
      'an active subscriber can renew in CLXAI without losing the current badge setting',
      (tester) async {
    final native = MainnetTestCommands();
    await screen(tester, native);
    expect(find.textContaining('Devnet'), findsNothing);
    await tester.tap(find.text('CLXAI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add 30 days'));
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
    final billing = RecoveryRefreshBilling();
    await screen(tester, native, billing: billing);
    await tester.ensureVisible(find.text('Recover purchase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recover purchase'));
    await tester.pumpAndSettle();
    expect(find.text('ABCDEF12'), findsOneWidget);
    expect(await readQr(tester), 'https://billing.example/recover/session');
    expect(find.textContaining('private-poll-token'), findsNothing);
    await tester.ensureVisible(find.text('Refresh status'));
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(billing.recoveryChecks, 1);
  });
}

Future<void> screen(WidgetTester tester, MainnetTestCommands native,
    {bool salesEnabled = true, MainnetTestBilling? billing}) async {
  final container = ProviderContainer(overrides: [
    plusConfigProvider.overrideWithValue(mainnetConfig),
    plusCommandsProvider.overrideWithValue(native),
    plusBillingProvider.overrideWithValue(
        (billing ?? MainnetTestBilling())..enabled = salesEnabled),
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

class RecoveryRefreshBilling extends MainnetTestBilling {
  int recoveryChecks = 0;
  @override
  Future<Map<String, dynamic>> recoveryStatus(PlusRecoverySession session,
      {String? after}) async {
    recoveryChecks++;
    return {...await startRecovery(mainnetSeries, session), 'orders': []};
  }
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
