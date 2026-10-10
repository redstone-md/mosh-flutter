import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real record plugin through its platform method protocol.
class VoiceRecorderProbe {
  VoiceRecorderProbe(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    final cache = Directory.systemTemp.createTempSync('mosh-voice-test');
    messenger.setMockMethodCallHandler(_record, _handle);
    messenger.setMockMethodCallHandler(
        _paths,
        (call) async =>
            call.method == 'getApplicationCacheDirectory' ? cache.path : null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_record, null);
      messenger.setMockMethodCallHandler(_paths, null);
      cache.deleteSync(recursive: true);
    });
  }

  static const _record = MethodChannel('com.llfbandit.record/messages');
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  final calls = <String>[];
  Completer<bool>? permission;
  Completer<void>? starting;
  bool recording = false;
  String? path;

  int count(String method) => calls.where((call) => call == method).length;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'hasPermission':
        return permission?.future ?? true;
      case 'start':
        path = (call.arguments as Map)['path'] as String;
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
        return {'current': -60.0, 'max': -60.0};
      case 'isEncoderSupported':
        return true;
      default:
        return null;
    }
  }
}
