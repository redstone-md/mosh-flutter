// RingtonePlayer -- the seam between the call modals and an actual audio
// synth. React's `ringtone.ts` builds a two-tone trill (440/480 Hz sine,
// 0.4 s on / 0.6 s off, 30 s backstop) with Web Audio. Flutter has no
// in-tree Web-Audio equivalent; the real synth (oscillator via
// `flutter_soloud` / `audioplayers` looping a generated WAV) is a later
// slice. To keep the call-modal widgets parity-first and unit-testable
// without a native audio backend, the modals take a [RingtonePlayer]
// and call `start()` on mount + `stop()` on dispose -- exactly mirroring
// React's `ringtoneRef.current = startRingtone()` / `ringtoneRef.current
// ?.stop()` lifecycle.
//
// The default [NoopRingtonePlayer] does nothing (no audio device in the
// headless test harness); the real impl will land in a later atomic and
// be injected from DmScreen.

library;

/// A handle to a started ringtone -- mirrors React's `RingtoneHandle`
/// (`{ stop(): void }`). The modal holds this from `start()` until
/// `dispose()`, then calls `stop()`.
abstract class RingtoneHandle {
  void stop();
}

/// The seam the call modals call. `start()` returns a [RingtoneHandle]
/// that the modal `stop()`s on dispose; `start()` is a no-op-safe call
/// (React wraps `startRingtone()` in `try/catch` and tolerates a null
/// ref).
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
/// Used by tests + as the fallback before the real audio synth lands.
class NoopRingtonePlayer implements RingtonePlayer {
  const NoopRingtonePlayer();
  @override
  RingtoneHandle start() => const _NoopHandle();
}
