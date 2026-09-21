// RingtonePlayer is the testable seam between call modals and the native
// CPAL synth. The production binding lives in cpal_ringtone.dart; this file
// keeps the inert default used by isolated widget tests.

library;

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
