import 'package:mosh/src/features/wake/wake_client.dart';

/// The wake service this build registers with, from the build (the
/// `MOSH_WAKE_URL` define); empty in builds that do not register.
const kWakeServiceUrl = String.fromEnvironment('MOSH_WAKE_URL');

/// The iPhone's side of registration: its push tokens and the Keychain slot
/// that keeps the registration.
abstract interface class WakeDevice {
  /// Null until the system has handed out the tokens.
  Future<WakeTokens?> tokens();
  Future<String?> loadRegistration();
  Future<void> saveRegistration(String registration);
}

/// Keeps this iPhone registered with its wake service and its handle
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

  Future<void> run() async {
    final tokens = await device.tokens();
    if (tokens == null) return;
    final registration = await _current(tokens);
    await device.saveRegistration(registration.toJson());
    await announce(service.toString(), registration.handle);
  }

  /// The stored registration, brought up to date, or a new one when there is
  /// none for this service or the service lost it.
  Future<WakeRegistration> _current(WakeTokens tokens) async {
    final stored = WakeRegistration.tryParse(await device.loadRegistration());
    if (stored == null || stored.service != service) {
      return client.register(service, tokens);
    }
    if (stored.tokens == tokens) return stored;
    return await client.update(stored, tokens)
        ? stored.withTokens(tokens)
        : client.register(service, tokens);
  }
}
