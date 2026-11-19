import 'dart:async';
import 'dart:io' show HttpException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/rust/api/wake.dart' as api;
import 'package:mosh/src/state/notifications_provider.dart';

import 'wake_client.dart';
import 'wake_previews.dart';
import 'wake_registration.dart';
import 'wake_sender.dart';

/// The production sender: asks the runtimes every second. They wake
/// members only through this build's service, so a build without one
/// wakes nobody.
WakeSender? startWakeSender(Ref ref) {
  if (kWakeServiceUrl.isEmpty) return null;
  // Spelled as the phone announces it (WakeRegistrar).
  unawaited(api.setWakeService(service: Uri.parse(kWakeServiceUrl).toString()));
  final sender = WakeSender(
      take: api.takeWakeRequests,
      forget: (handle) => api.forgetWakeHandle(handle: handle),
      refused: (request) =>
          api.wakeRefused(chat: request.chat, handle: request.handle));
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
  // Missed now, the next tick writes it; until then the extension shows
  // "New message" for a chat whose key it lacks.
  final previews =
      WakePreviews(read: api.previewChats, save: device.savePreviews);
  final sync = Timer.periodic(const Duration(seconds: 1),
      (_) => unawaited(previews.sync().catchError((Object _) {})));
  ref.onDispose(() {
    sync.cancel();
    device.onTokens = null;
    client.close();
  });
});
