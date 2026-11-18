import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/voice_call/system_call_mirror.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/features/wake/wake_registration.dart';

/// The iPhone runner's call screen (CallKit), its push tokens and the
/// Keychain slot of the wake registration, all in
/// `ios/Runner/SystemCalls.swift`.
final class IosSystemCalls implements SystemCallScreen, WakeDevice {
  IosSystemCalls() {
    _channel.setMethodCallHandler(_receive);
  }

  static const _channel = MethodChannel('app.mosh/system-calls');
  void Function(SystemCallAction action)? _onAction;

  /// Runs when the system hands out new push tokens.
  void Function()? onTokens;

  /// Attaching also takes what the user did on the call screen before Dart
  /// was running.
  @override
  set onAction(void Function(SystemCallAction action)? handler) {
    _onAction = handler;
    if (handler != null) unawaited(_channel.invokeMethod<void>('ready'));
  }

  @override
  Future<void> show(String callId, SystemCallKind kind, String name) =>
      _channel.invokeMethod<void>(
          'show', {'call': callId, 'kind': kind.name, 'name': name});

  @override
  Future<void> ended(String callId) =>
      _channel.invokeMethod<void>('ended', {'call': callId});

  @override
  Future<WakeTokens?> tokens() async {
    final tokens = await _channel.invokeMapMethod<String, String>('tokens');
    return tokens == null ? null : WakeTokens.fromJson(tokens);
  }

  @override
  Future<String?> loadRegistration() =>
      _channel.invokeMethod<String>('loadRegistration');

  @override
  Future<void> saveRegistration(String registration) =>
      _channel.invokeMethod<void>('saveRegistration', registration);

  Future<void> _receive(MethodCall call) async {
    if (call.method == 'tokens') {
      onTokens?.call();
      return;
    }
    final args = call.arguments as Map;
    final id = args['call'] as String;
    final action = switch (call.method) {
      'answer' => SystemCallAnswer(id),
      'end' => SystemCallEnd(id),
      'mute' => SystemCallMute(id, muted: args['muted'] == true),
      _ => null,
    };
    if (action != null) _onAction?.call(action);
  }
}

/// The iPhone's system calls; null on every other platform and in tests.
final iosSystemCallsProvider = Provider<IosSystemCalls?>((ref) => null);
