import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_qr_scanner.dart';
import 'package:mosh/src/features/device_link/qr_image.dart';

import '../../support/device_link_fixture.dart';
import '../../support/pump.dart';
import '../../support/scanner_platform.dart';

Future<void> _open(WidgetTester tester, ValueChanged<String?> onResult,
    {Completer<void>? returned,
    DeviceQrScanner scanner = const DeviceQrScanner()}) async {
  await pumpScreen(
      tester,
      Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      onResult(await Navigator.of(context).push<String>(
                          MaterialPageRoute(builder: (_) => scanner)));
                      returned?.complete();
                    },
                    child: const Text('Open scanner')),
              )));
  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
}

/// Observe the exact Future awaited by the scanner; QR decoding stays real.
class _FrameDecodeProbe {
  Completer<void> started = Completer<void>();
  Future<void>? hold;
  Future<String?>? pending;
  int calls = 0;

  Future<String?> decode(QrFrame frame) {
    final future = _decode(frame, hold);
    pending = future;
    calls++;
    if (!started.isCompleted) started.complete();
    return future;
  }

  Future<String?> _decode(QrFrame frame, Future<void>? release) async {
    final result = await decodeQrFrame(frame);
    if (release != null) await release;
    return result;
  }

  Future<void> sendAndWait(WidgetTester tester, ScannerPlatform hardware,
      CameraImageData frame) async {
    started = Completer<void>();
    hardware.frames.add(frame);
    await started.future;
    await pending!;
    // The scanner resumes its own await and clears _decoding before the next
    // frame; no wall-clock interval or second decode acts as a barrier.
    await tester.pump();
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
    await tester.runAsync(() async {
      final hardware = _install(ScannerPlatform());
      final results = <String?>[];
      final returned = Completer<void>();
      final release = Completer<void>();
      final decoder = _FrameDecodeProbe()..hold = release.future;
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      await _open(tester, results.add,
          returned: returned,
          scanner: DeviceQrScanner(decodeFrame: decoder.decode));
      await hardware.streaming;
      final scanner = tester.state(find.byType(DeviceQrScanner));
      hardware.frames.add(blankCameraFrame());
      await decoder.started.future;
      final uri = deviceLinkQrFixture();
      // A valid frame arriving during a slow negative decode is dropped.
      hardware.frames.add(qrCameraFrame(uri));
      await tester.pump();
      expect(decoder.calls, 1);
      expect(results, isEmpty);
      decoder.hold = null;
      release.complete();
      await decoder.pending!;
      await tester.pump();
      expect(tester.state(find.byType(DeviceQrScanner)), same(scanner));
      expect((hardware.starts, hardware.releases), (1, 0));
      hardware.frames
        ..add(qrCameraFrame(uri))
        ..add(qrCameraFrame(uri));
      await tester.pump();
      expect(decoder.calls, 2);
      await returned.future;
      await tester.pumpAndSettle();
      await hardware.released;
      expect(results, [uri]);
      expect(find.text('Open scanner'), findsOneWidget);
      expect(find.byType(DeviceQrScanner), findsNothing);
      expect(hardware.releases, hardware.starts);
    });
  });

  testWidgets('a broken frame does not stop scanning', (tester) async {
    await tester.runAsync(() async {
      final hardware = _install(ScannerPlatform());
      final results = <String?>[];
      final returned = Completer<void>();
      final decoder = _FrameDecodeProbe();
      await _open(tester, results.add,
          returned: returned,
          scanner: DeviceQrScanner(decodeFrame: decoder.decode));
      await hardware.streaming;
      final scanner = tester.state(find.byType(DeviceQrScanner));
      await decoder.sendAndWait(tester, hardware, brokenCameraFrame());
      expect(results, isEmpty);
      expect(tester.state(find.byType(DeviceQrScanner)), same(scanner));
      expect((hardware.starts, hardware.releases), (1, 0));
      final uri = deviceLinkQrFixture();
      hardware.frames.add(qrCameraFrame(uri));
      await tester.pump();
      expect(decoder.calls, 2);
      await returned.future;
      await tester.pumpAndSettle();
      expect(results, [uri]);
    });
  });

  testWidgets('leaving while the camera opens closes it; return reopens it',
      (tester) async {
    await tester.runAsync(() async {
      final opening = Completer<void>();
      final hardware = _install(ScannerPlatform(opening: opening));
      final results = <String?>[];
      final returned = Completer<void>();
      await _open(tester, results.add, returned: returned);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      opening.complete();
      await tester.pumpAndSettle();
      await hardware.released;
      expect((hardware.starts, hardware.releases), (1, 1));
      expect(find.textContaining('unavailable'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(hardware.starts, 2);
      final uri = deviceLinkQrFixture();
      await hardware.streaming;
      hardware.frames.add(qrCameraFrame(uri));
      await returned.future;
      await tester.pumpAndSettle();
      expect(results, [uri]);
    });
  });

  testWidgets(
      'camera stops in background and restarts on return; fallback cancels scan',
      (tester) async {
    final hardware = _install(ScannerPlatform());
    final results = <String?>[];
    await _open(tester, results.add);
    expect(hardware.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(hardware.releases, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(hardware.starts, 2);
    await tester.tap(find.text('Use an image or link'));
    await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(tester.takeException(), isNull);
    });
  }
}
