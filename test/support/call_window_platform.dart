import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Native window-channel fixture using the plugin's public wire protocol.
class CallWindowPlatform {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  String windowId = 'parent';
  String arguments = '';
  String? token;
  bool failCreate = false;
  bool failPresent = false;
  bool autoReady = true;
  static const windows = MethodChannel('mixin.one/desktop_multi_window');
  static const channels =
      MethodChannel('mixin.one/desktop_multi_window/channels');

  void install() {
    messenger.setMockMethodCallHandler(windows, (call) async {
      calls.add(call);
      if (call.method == 'getWindowDefinition') {
        return {'windowId': windowId, 'windowArgument': arguments};
      }
      if (call.method == 'createWindow') {
        if (failCreate) throw PlatformException(code: 'unavailable');
        final config = call.arguments as Map;
        final args = jsonDecode(config['arguments'] as String) as Map;
        token = args['token'] as String;
        if (autoReady) await deliver(windowId, 'call-ready', {'token': token});
        return 'child';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      calls.add(call);
      final args = call.arguments as Map;
      if (call.method == 'invokeMethod' &&
          args['method'] == 'call-present' &&
          failPresent) {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
  }

  Future<Object?> deliver(String id, String method, [Object? arguments]) async {
    final codec = const StandardMethodCodec();
    final reply = Completer<ByteData?>();
    messenger.handlePlatformMessage(
        channels.name,
        codec.encodeMethodCall(MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/$id',
          'method': method,
          'arguments': arguments,
        })),
        reply.complete);
    final data = await reply.future;
    return data == null ? null : codec.decodeEnvelope(data);
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  }
}
