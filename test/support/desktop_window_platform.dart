import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';

/// Native window seam; records commands and delivers ordinary plugin events.
class DesktopWindowPlatform {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Map<String, Object?> configuration = {};
  Future<void>? maximizeCompletion;
  Future<void>? restoreCompletion;
  Future<void> Function()? duringWindowSetup;
  static const manager = MethodChannel('window_manager');

  void install() {
    messenger.setMockMethodCallHandler(manager, (call) async {
      calls.add(call);
      if (call.method == 'maximize') await maximizeCompletion;
      if (call.method == 'unmaximize') await restoreCompletion;
      if (call.method == 'setTitleBarStyle') await duringWindowSetup?.call();
      if (call.method.startsWith('is')) return call.method == 'isFocused';
      return null;
    });
    messenger.setMockMethodCallHandler(DesktopWindowController.channel,
        (call) async {
      calls.add(call);
      return call.method == 'configure' ? configuration : null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(manager, null);
      messenger.setMockMethodCallHandler(DesktopWindowController.channel, null);
    });
  }

  Future<void> send(MethodChannel channel, MethodCall call) async {
    final reply = Completer<ByteData?>();
    messenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(call), reply.complete);
    await reply.future;
  }

  Future<void> event(String name) =>
      send(manager, MethodCall('onEvent', {'eventName': name}));
}
