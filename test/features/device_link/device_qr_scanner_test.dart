import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  await _settle(tester);
}

/// Lets camera calls and off-thread QR decoding finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
}

ScannerPlatform _install(ScannerPlatform hardware) {
  final previous = CameraPlatform.instance;
  CameraPlatform.instance = hardware;
  addTearDown(() {
    CameraPlatform.instance = previous;
    hardware.frames.close();
  });
  return hardware;
}

void main() {
  testWidgets(
      'camera ignores frames without a QR and returns one URI, then releases camera',
      (tester) async {
    final hardware = _install(ScannerPlatform());
    final results = <String?>[];
    await _open(tester, results.add);
    hardware.frames.add(blankCameraFrame());
    await _settle(tester);
    expect(results, isEmpty);
    final uri = deviceLinkQrFixture();
    hardware.frames
      ..add(qrCameraFrame(uri))
      ..add(qrCameraFrame(uri));
    await _settle(tester);
    expect(results, [uri]);
    expect(find.text('Open scanner'), findsOneWidget);
    expect(find.byType(DeviceQrScanner), findsNothing);
    expect(hardware.releases, hardware.starts);
  });

  testWidgets('a broken frame does not stop scanning', (tester) async {
    final hardware = _install(ScannerPlatform());
    final results = <String?>[];
    await _open(tester, results.add);
    hardware.frames.add(brokenCameraFrame());
    await _settle(tester);
    final uri = deviceLinkQrFixture();
    hardware.frames.add(qrCameraFrame(uri));
    await _settle(tester);
    expect(results, [uri]);
  });

  testWidgets('leaving while the camera opens closes it; return reopens it',
      (tester) async {
    final opening = Completer<void>();
    final hardware = _install(ScannerPlatform(opening: opening));
    final results = <String?>[];
    await _open(tester, results.add);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    opening.complete();
    await _settle(tester);
    expect((hardware.starts, hardware.releases), (1, 1));
    expect(find.textContaining('unavailable'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(hardware.starts, 2);
    final uri = deviceLinkQrFixture();
    hardware.frames.add(qrCameraFrame(uri));
    await _settle(tester);
    expect(results, [uri]);
  });

  testWidgets(
      'camera stops in background and restarts on return; fallback cancels scan',
      (tester) async {
    final hardware = _install(ScannerPlatform());
    final results = <String?>[];
    await _open(tester, results.add);
    expect(hardware.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _settle(tester);
    expect(hardware.releases, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(hardware.starts, 2);
    await tester.tap(find.text('Use an image or link'));
    await _settle(tester);
    expect(results, [null]);
    expect(hardware.releases, 2);
  });

  testWidgets('a camera that cannot stream is released and reported',
      (tester) async {
    final hardware = _install(ScannerPlatform(streamFails: true));
    await _open(tester, (_) {});
    expect(find.textContaining('The camera is unavailable'), findsOneWidget);
    expect((hardware.starts, hardware.releases), (1, 1));
  });

  for (final (name, hardware, message) in [
    (
      'denied permission',
      () => ScannerPlatform(errorCode: 'CameraAccessDenied'),
      'Allow camera access'
    ),
    (
      'no camera',
      () => ScannerPlatform(cameras: const []),
      'The camera is unavailable'
    ),
  ]) {
    testWidgets('$name keeps the image/link alternative available',
        (tester) async {
      _install(hardware());
      final results = <String?>[];
      await _open(tester, results.add);
      expect(find.textContaining(message), findsOneWidget);
      await tester.tap(find.text('Use an image or link'));
      await _settle(tester);
      expect(results, [null]);
      expect(tester.takeException(), isNull);
    });
  }
}
