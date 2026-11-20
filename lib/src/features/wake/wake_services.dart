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

/// This phone's side of waking: the iPhone's system calls, or Android's
/// push service; null elsewhere and in tests.
final wakeDeviceProvider =
    Provider<WakeDevice?>((ref) => ref.watch(iosSystemCallsProvider));

/// Keeps this phone registered with the build's wake service while the
/// process lives; does nothing elsewhere, without a service, or in a build
/// no push service wakes.
final wakeRegistrationProvider = Provider<void>((ref) {
  final device = ref.watch(wakeDeviceProvider);
  if (device == null || kWakeServiceUrl.isEmpty) return;
  final client = WakeClient();
  Timer? sync;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    sync?.cancel();
    device.onTokens = null;
    client.close();
  });
  unawaited(device.wakeable().then((wakeable) {
    if (wakeable && !disposed) sync = _keepRegistered(ref, device, client);
  },
      onError: (Object error) => api.noteWakeRegistration(
          problem: 'push service unknown: ${error.runtimeType}')));
});

/// Registers now and whenever the tokens change, and keeps the chats'
/// preview keys where the push's receiver reads them; the timer that does
/// the latter is returned for disposal.
Timer _keepRegistered(Ref ref, WakeDevice device, WakeClient client) {
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
        await api.noteWakeRegistration(problem: 'no push token yet');
      }
    } on HttpException catch (error) {
      await api.noteWakeRegistration(problem: error.message);
    } on Object catch (error) {
      await api.noteWakeRegistration(
          problem: 'registration failed: ${error.runtimeType}');
    }
  }

  // Message alerts show only with this permission.
  unawaited(ref.read(notificationsReadyProvider.future));
  device.onTokens = () => unawaited(run());
  unawaited(run());
  // Missed now, the next tick writes it; until then the receiver shows
  // "New message" for a chat whose key it lacks.
  final previews =
      WakePreviews(read: api.previewChats, save: device.savePreviews);
  return Timer.periodic(const Duration(seconds: 1),
      (_) => unawaited(previews.sync().catchError((Object _) {})));
}
