import 'package:flutter/services.dart';
import 'package:mosh/src/features/wake/wake_client.dart';
import 'package:mosh/src/features/wake/wake_registration.dart';

/// This Android phone's wake registration, in
/// `android/app/src/main/kotlin/app/mosh/mosh/MoshWake.kt`: the build's push
/// address (a Firebase installation id in the Google Play and GitHub builds,
/// none in F-Droid's) and the sealed slots its messaging service reads
/// while Mosh is closed.
final class AndroidWake implements WakeDevice {
  AndroidWake() {
    _channel.setMethodCallHandler(_receive);
  }

  static const _channel = MethodChannel('app.mosh.mosh/wake');

  @override
  void Function()? onTokens;

  @override
  Future<bool> wakeable() async =>
      await _channel.invokeMethod<bool>('wakeable') ?? false;

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

  @override
  Future<void> savePreviews(String chats) =>
      _channel.invokeMethod<void>('savePreviews', chats);

  Future<void> _receive(MethodCall call) async {
    if (call.method == 'tokens') onTokens?.call();
  }
}
