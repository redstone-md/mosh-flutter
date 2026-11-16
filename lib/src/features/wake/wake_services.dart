import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as api;

import 'wake_client.dart';
import 'wake_registration.dart';
import 'wake_sender.dart';

/// The production sender: asks the DM runtime every second.
WakeSender startWakeSender(Ref ref) {
  final sender = WakeSender(
      take: api.takeWakeRequests,
      forget: (handle) => api.forgetWakeHandle(handle: handle));
  sender.start(const Duration(seconds: 1));
  ref.onDispose(sender.dispose);
  return sender;
}

/// Keeps this iPhone registered with the build's wake service while the
/// process lives; does nothing elsewhere or without a service.
final wakeRegistrationProvider = Provider<void>((ref) {
  final device = ref.watch(iosSystemCallsProvider);
  if (device == null || kWakeServiceUrl.isEmpty) return;
  final client = WakeClient();
  final registrar = WakeRegistrar(
      service: Uri.parse(kWakeServiceUrl),
      device: device,
      client: client,
      announce: (service, handle) =>
          api.setWakeAddress(service: service, handle: handle));
  Future<void> run() => registrar.run().catchError((Object error) {
        // Retried with the next launch or token change; until then contacts
        // keep the handle they have.
        debugPrint('wake registration failed: ${error.runtimeType}');
      });
  device.onTokens = () => unawaited(run());
  unawaited(run());
  ref.onDispose(() {
    device.onTokens = null;
    client.close();
  });
});
