/// A handle to a started ringtone. The modal holds this from `start()` until
/// `dispose()`, then calls `stop()`.
abstract class RingtoneHandle {
  void stop();
}

/// The seam the call modals call. `start()` returns a [RingtoneHandle]
/// that the modal `stop()`s on dispose; callers tolerate a failed
/// `start()` (the modals wrap it in `try/catch`).
abstract class RingtonePlayer {
  RingtoneHandle start();
}

/// A [RingtoneHandle] whose `stop()` is inert -- returned by
/// [NoopRingtonePlayer] so the modals' `stop()` call is always safe.
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
