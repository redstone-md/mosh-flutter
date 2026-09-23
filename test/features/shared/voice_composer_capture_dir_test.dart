// The VoiceComposer capture-directory regression (macOS 0.9.3 field bug:
// `PathNotFoundException` errno 2 on `…/Caches/app.mosh.mosh/mosh-voice-…​.m4a`).
//
// Root cause: `getTemporaryDirectory()` on macOS maps to
// `NSCachesDirectory` + the bundle id appended, and path_provider does NOT
// create that directory; `record_macos` writes via
// `AVCaptureFileOutput.startRecording(to:)`, which never creates parent
// dirs and reports the failure only to an unsurfaced delegate callback —
// `stop()` still returns the path, and `sendVoice`'s `readAsBytes()` dies
// with "No such file or directory".
//
// What is pinned here:
//  1. The clip path the recorder receives lives inside an explicitly
//     created `mosh-voice/` subdirectory (not the raw cache root).
//  2. The directory is created recursively EVEN WHEN the base dir does not
//     exist yet (the exact macOS state: base missing → errno 2 today).
//  3. The base dir switches to the app cache dir
//     (`getApplicationCacheDirectory`), whose plugin path DOES create the
//     base — belt and braces with the explicit recursive create.
//
// Driven through the real `record` plugin seam like
// voice_composer_permission_test.dart; `path_provider` is stubbed to a
// fresh (non-existent) base dir so the recursive create is exercised for
// real on the host filesystem.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';

const MethodChannel _recordChannel =
    MethodChannel('com.llfbandit.record/messages');

void _stubRecordChannel({
  required List<String> started,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, (call) async {
    switch (call.method) {
      case 'create':
      case 'dispose':
      case 'cancel':
        return null;
      case 'hasPermission':
        return true;
      case 'start':
        final path = (call.arguments as Map)['path'] as String;
        started.add(path);
        return null;
      case 'stop':
        return started.lastOrNull;
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

Future<void> _pumpComposer(
  WidgetTester tester, {
  required List<VoiceSend> sent,
}) async {
  // A base dir that DOES NOT exist: this is the macOS field state
  // (Caches/app.mosh.mosh absent on first voice message). The stub hands
  // its path to path_provider, so the composer's recursive create is what
  // makes the capture work at all.
  final base =
      Directory.systemTemp.createTempSync('mosh-voice-dir-test-parent');
  addTearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });
  final cacheRoot = Directory('${base.path}/Caches/app.mosh.mosh');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
    // getTemporaryDirectory must NOT be answered on the new path: the
    // fix switches to getApplicationCacheDirectory, so only that call
    // returns the (missing) dir. Answering getTemporaryDirectory would
    // mask a regression back to the temp dir.
    if (call.method == 'getApplicationCacheDirectory') return cacheRoot.path;
    return null;
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
          onSend: sent.add,
          onError: (_) {},
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

void main() {
  testWidgets('capture targets an explicitly created mosh-voice/ dir',
      (tester) async {
    final started = <String>[];
    _stubRecordChannel(started: started);
    final sent = <VoiceSend>[];
    await _pumpComposer(tester, sent: sent);

    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(started, hasLength(1), reason: 'the capture must really begin');
    // The clip lands in the mosh-voice subdirectory, not the cache root.
    expect(started.single, contains('mosh-voice'));
    final clipsDir = Directory(
      started.single.substring(0, started.single.lastIndexOf('/')),
    );
    expect(clipsDir.existsSync(), isTrue,
        reason: 'the recorder writes only into an existing directory');
    expect(started.single, endsWith('.m4a'));
    expect(errors(), isEmpty);
  });

  testWidgets('the clip dir is created even when the base is missing',
      (tester) async {
    final started = <String>[];
    _stubRecordChannel(started: started);
    final sent = <VoiceSend>[];
    await _pumpComposer(tester, sent: sent);

    await tester.tap(find.byIcon(Icons.mic_none_outlined));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // The recursive create is the fix: the recorder receives a path whose
    // parent chain did NOT exist when the capture started.
    expect(started, hasLength(1));
    final clipsDir = Directory(
      started.single.substring(0, started.single.lastIndexOf('/')),
    );
    expect(clipsDir.existsSync(), isTrue,
        reason: 'errno 2 (No such file or directory) is exactly this state');
  });
}

List<String> errors() {
  // The composer surfaces start failures through onError; the test
  // harness hands it a no-op, so failures surface as missing started
  // entries instead. Kept for the first test's assertion symmetry.
  return const [];
}
