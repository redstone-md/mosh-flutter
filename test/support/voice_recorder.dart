import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart' show moshThemeData;
import 'package:mosh/src/features/shared/media_player.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';

/// The names of the voice controls in tests.
const testVoiceLabels = VoiceComposerLabels(
  record: 'Record',
  cancel: 'Cancel',
  pause: 'Pause',
  resume: 'Resume',
  discard: 'Discard',
  play: 'Play',
  pausePlayback: 'Pause playback',
  send: 'Send voice',
  permissionDenied: 'mic denied',
);

/// Stands in for mosh-core's join: writes the clip and remembers what it
/// was made of.
class VoiceJoinProbe {
  final joined = <List<String>>[];
  final outputs = <String>[];

  Future<void> call(
      {required List<String> segments, required String output}) async {
    joined.add(segments);
    outputs.add(output);
    File(output).writeAsBytesSync([4, 5, 6]);
  }
}

/// A [VoiceComposer] on its own, whose row at rest is just the microphone.
/// Pump a [VoiceRecorderProbe] first.
Future<void> pumpVoiceComposer(
  WidgetTester tester, {
  List<VoiceSend>? sent,
  List<String>? errors,
  VoiceSegmentJoin? join,
  MediaPlayerFactory createPlayer = createMediaPlayer,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: moshThemeData,
    home: Scaffold(
      body: Center(
        child: VoiceComposer(
          disabled: false,
          labels: testVoiceLabels,
          onSend: sent?.add ?? (_) {},
          onError: errors?.add ?? (_) {},
          idle: (_, microphone) => microphone,
          inputDeviceId: () => null,
          createPlayer: createPlayer,
          joinSegments: join ?? VoiceJoinProbe().call,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Lets the recorder's platform calls and the row's cross-fade finish.
/// Fixed frames, not a settle: a live recording ticks for ever.
Future<void> pumpVoiceFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drives the real record plugin through its platform method protocol.
class VoiceRecorderProbe {
  /// [cache] is the app cache directory the recorder is told about; it
  /// need not exist.
  VoiceRecorderProbe(WidgetTester tester, {Directory? cache}) {
    final messenger = tester.binding.defaultBinaryMessenger;
    final root = Directory.systemTemp.createTempSync('mosh-voice-test');
    cache ??= root;
    messenger.setMockMethodCallHandler(_record, _handle);
    messenger.setMockMethodCallHandler(
        _paths,
        (call) async =>
            call.method == 'getApplicationCacheDirectory' ? cache!.path : null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_record, null);
      messenger.setMockMethodCallHandler(_paths, null);
      root.deleteSync(recursive: true);
    });
  }

  static const _record = MethodChannel('com.llfbandit.record/messages');
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  final calls = <String>[];

  /// Every file a capture was started into, in order.
  final started = <String>[];

  /// Makes the next capture fail to start, as a busy device does.
  bool failStart = false;

  /// What the microphone hears, dBFS.
  double level = -60;

  /// What a permission request answers; [permission] holds it back.
  bool allowed = true;
  Completer<bool>? permission;
  Completer<void>? starting;
  bool recording = false;
  String? path;

  int count(String method) => calls.where((call) => call == method).length;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'hasPermission':
        return permission?.future ?? allowed;
      case 'start':
        if (failStart) throw PlatformException(code: 'record', message: 'busy');
        path = (call.arguments as Map)['path'] as String;
        started.add(path!);
        File(path!).writeAsBytesSync([1, 2, 3]);
        recording = true;
        await starting?.future;
        return null;
      case 'stop':
        recording = false;
        return path;
      case 'cancel':
      case 'dispose':
        recording = false;
        return null;
      case 'isRecording':
        return recording;
      case 'getAmplitude':
        return {'current': level, 'max': level};
      case 'isEncoderSupported':
        return true;
      default:
        return null;
    }
  }
}
