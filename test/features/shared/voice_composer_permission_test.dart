// The VoiceComposer permission flow, driven through the real `record`
// plugin seam (the `com.llfbandit.record/messages` method channel), the
// same channel-stubbing pattern the repo already uses for `window_manager`
// and `desktop_drop`.
//
// What is pinned here:
//  1. Mounting the composer must NOT probe the mic — the 0.9.1 macOS
//     crash died in TCC because the probe fired at chat open, before the
//     plist had a usage string. The mic button renders regardless.
//  2. A tap with permission granted starts the recording phase.
//  3. A tap with permission refused surfaces the localized denial label
//     through onError and keeps the mic button (a later grant can retry).
//  4. Stopping lands in the review phase; send hands a VoiceSend over.
//
// The channel stub answers the recorder's real protocol (`create`,
// `hasPermission`, `start`, `stop`, `isRecording`, `getAmplitude`,
// `dispose`), so the plugin's Dart-side framing (semaphore, amplitude
// timer wiring) runs for real. `getTemporaryDirectory` is stubbed to a
// real temp dir so the capture writes to a real filesystem path.
//
// No `pumpAndSettle` once a recording is live: the composer's elapsed
// timer is periodic (setState every 200 ms), so settling never ends —
// the tests pump fixed frames instead.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';

const MethodChannel _recordChannel =
    MethodChannel('com.llfbandit.record/messages');

/// Answers the `record` plugin's method protocol. [permissionResult] is
/// what `hasPermission` reports. `stop` returns the path the last `start`
/// was given, mirroring the real recorder (its stop() reports the file).
void _stubRecordChannel({
  required bool Function() permissionResult,
  List<String>? started,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, (call) async {
    switch (call.method) {
      case 'create':
      case 'dispose':
      case 'cancel':
        return null;
      case 'hasPermission':
        return permissionResult();
      case 'start':
        final path = (call.arguments as Map)['path'] as String;
        started?.add(path);
        return null;
      case 'stop':
        return started?.lastOrNull;
      case 'isRecording':
        return false;
      case 'getAmplitude':
        return {'current': -60.0, 'max': -60.0};
      case 'isEncoderSupported':
        return true;
      default:
        return null;
    }
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, null));
}

/// Records every method call, for the mount-time probe assertion.
List<String> _recordCalls() {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, (call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'create':
      case 'dispose':
      case 'cancel':
      case 'start':
      case 'stop':
        return null;
      case 'hasPermission':
        return true;
      case 'isRecording':
        return false;
      case 'getAmplitude':
        return {'current': -60.0, 'max': -60.0};
      case 'isEncoderSupported':
        return true;
      default:
        return null;
    }
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, null));
  return calls;
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required List<String> errors,
  List<VoiceSend>? sent,
}) async {
  // The capture asks the platform for the app cache dir (the clip dir
  // fix). Real async IO never resolves inside a widget test's fake async
  // zone, so the directory is created (and torn down) synchronously; the
  // stub answers the cache method, with a synchronous create of the
  // mosh-voice subdir skipped — the composer's own recursive create
  // handles it in the app.
  final dir = Directory.systemTemp.createTempSync('mosh-voice-test');
  addTearDown(() => dir.deleteSync(recursive: true));

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => switch (call.method) {
                'getApplicationCacheDirectory' => dir.path,
                _ => null,
              });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null));

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: VoiceComposer(
          disabled: false,
          onSend: sent?.add ?? (_) {},
          onError: errors.add,
          recordLabel: 'Record',
          discardLabel: 'Discard',
          stopLabel: 'Stop',
          playLabel: 'Play',
          sendLabel: 'Send voice',
          permissionDeniedLabel: 'mic denied',
          inputDeviceId: () => null,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _micButton() => find.byIcon(Icons.mic_none_outlined);

void main() {
  testWidgets('mount probes nothing; the mic button renders', (tester) async {
    final calls = _recordCalls();
    final errors = <String>[];
    await _pumpComposer(tester, errors: errors);

    // create runs at recorder construction; a permission probe
    // (hasPermission) at MOUNT is the crash class this rework kills.
    expect(calls, isNot(contains('hasPermission')),
        reason: 'the 0.9.1 macOS TCC crash fired the probe at chat open');
    expect(_micButton(), findsOneWidget);
  });

  testWidgets('tap with permission granted starts the recording phase',
      (tester) async {
    final started = <String>[];
    _stubRecordChannel(
      permissionResult: () => true,
      started: started,
    );
    final errors = <String>[];
    await _pumpComposer(tester, errors: errors);

    await tester.tap(_micButton());
    // Fixed frames, not settle: the elapsed timer is periodic.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(started, hasLength(1), reason: 'the capture must really begin');
    expect(started.single, endsWith('.m4a'));
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets(
      'tap with permission refused surfaces the denial and keeps '
      'the mic button', (tester) async {
    _stubRecordChannel(permissionResult: () => false);
    final errors = <String>[];
    await _pumpComposer(tester, errors: errors);

    await tester.tap(_micButton());
    await tester.pumpAndSettle();

    expect(errors, contains('mic denied'),
        reason: 'the refusal must surface through onError, not vanish');
    expect(find.byIcon(Icons.stop), findsNothing,
        reason: 'no recording may start on a refusal');
    expect(_micButton(), findsOneWidget,
        reason: 'a later grant must be able to retry from the button');
  });

  testWidgets('stop lands in review; send hands over the VoiceSend',
      (tester) async {
    final started = <String>[];
    _stubRecordChannel(
      permissionResult: () => true,
      started: started,
    );
    final errors = <String>[];
    final sent = <VoiceSend>[];
    await _pumpComposer(tester, errors: errors, sent: sent);

    await tester.tap(_micButton());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Review phase: play + discard + send icons.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.path, started.single,
        reason: 'the sent clip is the stopped capture file');
    expect(sent.single.mime, 'audio/mp4');
    expect(_micButton(), findsOneWidget, reason: 'back to idle after send');
    expect(errors, isEmpty);
  });
}
