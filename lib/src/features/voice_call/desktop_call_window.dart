import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'call_view_state.dart';
import 'call_window_coordinator.dart';
import 'process_call_window.dart';

/// The child engine presents metadata and sends commands. It initializes no
/// Rust runtime, database, recorder or playback factory.
class DesktopCallWindow implements CallWindowHandle {
  DesktopCallWindow._(this._parent, this._child);

  final WindowController _parent;
  final WindowController _child;
  bool _closed = false;
  static int _nextToken = 0;

  static Future<CallWindowHandle> open(
      Future<void> Function(CallViewCommand) onCommand) async {
    final parent = await WindowController.fromCurrentEngine();
    final ready = Completer<void>();
    final token = '${DateTime.now().microsecondsSinceEpoch}-${++_nextToken}';
    await parent.setWindowMethodHandler((call) async {
      final args = call.arguments;
      if (args is! Map || args['token'] != token) return null;
      if (call.method == 'call-ready' && !ready.isCompleted) {
        ready.complete();
      } else if (call.method == 'call-command') {
        await onCommand(CallViewCommand.fromMap(args));
      } else {
        throw MissingPluginException('Unknown call window method');
      }
      return null;
    });
    WindowController? child;
    try {
      child = await WindowController.create(WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'voice-call',
          'parent': parent.windowId,
          'token': token,
        }),
      ));
      await ready.future.timeout(const Duration(seconds: 10));
      return DesktopCallWindow._(parent, child);
    } catch (_) {
      if (child != null) {
        try {
          await child
              .invokeMethod<void>('call-close')
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          await child.hide();
        }
      }
      await parent.setWindowMethodHandler(null);
      rethrow;
    }
  }

  @override
  Future<void> present(CallViewState state) async {
    if (!_closed) {
      await _child.invokeMethod<void>('call-present', state.toMap());
    }
  }

  @override
  Future<void> show() async {
    if (!_closed) await _child.invokeMethod<void>('call-show');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _child
          .invokeMethod<void>('call-close')
          .timeout(const Duration(seconds: 2));
    } finally {
      await _parent.setWindowMethodHandler(null);
    }
  }
}

Future<CallWindowHandle> openDesktopCallWindow(
        Future<void> Function(CallViewCommand) onCommand) =>
    Platform.isLinux
        ? ProcessCallWindow.open(onCommand)
        : DesktopCallWindow.open(onCommand);
