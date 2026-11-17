import 'dart:async';
import 'dart:io' show HttpException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as api;
import 'package:mosh/src/state/notifications_provider.dart';

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
  // Retried with the next launch or token change; until then contacts keep
  // the handle they have. The field log says why, without the service's
  // address or any token.
  Future<void> run() async {
    try {
      if (!await registrar.run()) {
        await api.noteWakeRegistration(problem: 'no VoIP push token yet');
      }
    } on HttpException catch (error) {
      await api.noteWakeRegistration(problem: error.message);
    } on Object catch (error) {
      await api.noteWakeRegistration(
          problem: 'registration failed: ${error.runtimeType}');
    }
  }

  // iOS shows the service's message alerts only with this permission.
  unawaited(ref.read(notificationsReadyProvider.future));
  device.onTokens = () => unawaited(run());
  unawaited(run());
  ref.onDispose(() {
    device.onTokens = null;
    client.close();
  });
});
