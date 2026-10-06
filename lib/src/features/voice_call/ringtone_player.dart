/// A started ringtone. The call owner stops it on answer, rejection or end.
abstract class RingtoneHandle {
  void stop();
}

/// Audio backend boundary. Calls tolerate a failed start or stop.
abstract class RingtonePlayer {
  RingtoneHandle start();
}

/// A [RingtoneHandle] whose `stop()` is inert -- returned by
/// [NoopRingtonePlayer] so the owner's `stop()` call is always safe.
class _NoopHandle implements RingtoneHandle {
  const _NoopHandle();
  @override
  void stop() {}
}

/// Default [RingtonePlayer]: starts nothing, returns an inert handle.
class NoopRingtonePlayer implements RingtonePlayer {
  const NoopRingtonePlayer();
  @override
  RingtoneHandle start() => const _NoopHandle();
}
