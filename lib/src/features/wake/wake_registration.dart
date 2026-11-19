import 'package:mosh/src/features/wake/wake_client.dart';

/// The wake service this build registers with, from the build (the
/// `MOSH_WAKE_URL` define); empty in builds that do not register.
const kWakeServiceUrl = String.fromEnvironment('MOSH_WAKE_URL');

/// The phone's side of registration: its push address, the sealed slot
/// that keeps the registration, and where the chats' preview keys go for
/// whatever shows a woken message (iOS's notification extension, Android's
/// messaging service).
abstract interface class WakeDevice {
  /// Whether this build is woken through a push service at all; Android's
  /// F-Droid build is not.
  Future<bool> wakeable();

  /// Null until the system has handed out the tokens.
  Future<WakeTokens?> tokens();
  Future<String?> loadRegistration();
  Future<void> saveRegistration(String registration);
  Future<void> savePreviews(String chats);

  /// Runs when the system hands out new push tokens.
  set onTokens(void Function()? handler);
}

/// Keeps this phone registered with its wake service and its handle
/// announced in every chat. Run at launch and whenever the tokens change.
class WakeRegistrar {
  WakeRegistrar({
    required this.service,
    required this.device,
    required this.client,
    required this.announce,
  });

  final Uri service;
  final WakeDevice device;
  final WakeClient client;
  final Future<void> Function(String service, String handle) announce;

  Future<bool> _last = Future.value(true);

  /// False while the system has not handed out the push tokens. Runs one at
  /// a time: overlapping runs would each register their own handle.
  Future<bool> run() =>
      _last = _last.then((_) => _run(), onError: (Object _) => _run());

  Future<bool> _run() async {
    final tokens = await device.tokens();
    if (tokens == null) return false;
    final registration = await _current(tokens);
    await device.saveRegistration(registration.toJson());
    await announce(service.toString(), registration.handle);
    return true;
  }

  /// The stored registration, brought up to date, or a new one when there is
  /// none for this service or the service lost it.
  Future<WakeRegistration> _current(WakeTokens tokens) async {
    final stored = WakeRegistration.tryParse(await device.loadRegistration());
    if (stored == null || stored.service != service) {
      return client.register(service, tokens);
    }
    // Updated every run, so an entry the service lost is noticed and
    // replaced before its handle is announced again.
    return await client.update(stored, tokens)
        ? stored
        : client.register(service, tokens);
  }
}
