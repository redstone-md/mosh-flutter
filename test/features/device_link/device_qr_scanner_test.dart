import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mosh/src/features/device_link/device_qr_scanner.dart';

import '../../support/device_link_fixture.dart';
import '../../support/pump.dart';
import '../../support/scanner_platform.dart';

Future<void> _open(WidgetTester tester, ValueChanged<String?> onResult) async {
  await pumpScreen(
      tester,
      Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      onResult(await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                              builder: (_) => const DeviceQrScanner())));
                    },
                    child: const Text('Open scanner')),
              )));
  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
}

void main() {
  late MobileScannerPlatform previous;
  setUp(() => previous = MobileScannerPlatform.instance);
  tearDown(() => MobileScannerPlatform.instance = previous);

  testWidgets(
      'camera ignores empty captures and returns one URI, then releases camera',
      (tester) async {
    final hardware = ScannerPlatform();
    addTearDown(hardware.captures.close);
    MobileScannerPlatform.instance = hardware;
    final results = <String?>[];
    await _open(tester, results.add);
    hardware.captures.add(
        const BarcodeCapture(barcodes: [Barcode(), Barcode(rawValue: '')]));
    await tester.pump();
    expect(results, isEmpty);
    final uri = deviceLinkQrFixture();
    hardware.captures.add(BarcodeCapture(barcodes: [
      Barcode(rawValue: uri),
      const Barcode(rawValue: 'another capture')
    ]));
    hardware.captures.add(BarcodeCapture(barcodes: [Barcode(rawValue: uri)]));
    await tester.pumpAndSettle();
    expect(results, [uri]);
    expect(find.text('Open scanner'), findsOneWidget);
    await _finishExit(tester, hardware);
  });

  testWidgets(
      'camera stops in background and restarts on return; fallback cancels scan',
      (tester) async {
    final hardware = ScannerPlatform();
    addTearDown(hardware.captures.close);
    MobileScannerPlatform.instance = hardware;
    final results = <String?>[];
    await _open(tester, results.add);
    expect(hardware.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(hardware.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(hardware.starts, 2);
    await tester.tap(find.text('Use an image or link'));
    await tester.pumpAndSettle();
    expect(results, [null]);
    await _finishExit(tester, hardware);
  });

  for (final error in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported
  ]) {
    testWidgets('$error keeps the image/link alternative available',
        (tester) async {
      final hardware = ScannerPlatform(error: error);
      addTearDown(hardware.captures.close);
      MobileScannerPlatform.instance = hardware;
      final results = <String?>[];
      await _open(tester, results.add);
      expect(
          find.textContaining(error == MobileScannerErrorCode.permissionDenied
              ? 'Allow camera access'
              : 'The camera is unavailable'),
          findsOneWidget);
      await tester.tap(find.text('Use an image or link'));
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _finishExit(WidgetTester tester, ScannerPlatform hardware) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  expect(find.byType(DeviceQrScanner, skipOffstage: false), findsNothing);
  expect(hardware.stops, greaterThanOrEqualTo(1));
  expect(hardware.disposed, isTrue);
}
