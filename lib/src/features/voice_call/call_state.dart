/// 1-в-1 Dart port of React `src/features/private-dm/voice-call/
/// call-state.ts`. The pure voice-call state machine the
/// orchestration hook (`use-voice-call-orchestration.ts`) builds on.
/// Free of any I/O so it's unit-testable in isolation: given a
/// `CallPhase` + a `CallEvent` it returns the next phase, plus a pure
/// no-answer-timeout predicate.
library;

/// The phase a voice call is in. Mirrors React's
/// `type CallPhase = "idle" | "outgoing" | "ringing" | "active" | "ended"`.
enum CallPhase {
  idle,
  outgoing,
  ringing,
  active,
  ended,
}

/// The events that drive the state machine. Mirrors React's
/// discriminated-union `CallEvent` -- but since NONE of the events
/// carry a payload (each is just a `kind`), a plain Dart enum is the
/// idiomatic, exhaustive representation. React `kind` -> Dart value:
///   `local_dial`    -> [localDial]
///   `local_accept`  -> [localAccept]
///   `local_decline` -> [localDecline]
///   `local_end`     -> [localEnd]
///   `remote_offer`  -> [remoteOffer]
///   `remote_accept` -> [remoteAccept]
///   `remote_decline`-> [remoteDecline]
///   `remote_end`    -> [remoteEnd]
///   `no_answer`     -> [noAnswer]
enum CallEvent {
  localDial,
  localAccept,
  localDecline,
  localEnd,
  remoteOffer,
  remoteAccept,
  remoteDecline,
  remoteEnd,
  noAnswer,
}

/// Mirrors React's `NO_ANSWER_TIMEOUT_MS` (call-state.ts). The no-answer
/// window before an outgoing call auto-ends. One source of truth -- the
/// incoming-call modal sources its milliseconds from this so the two
/// never drift.
const int kNoAnswerTimeoutMs = 30000;

/// Pure transition: given [phase] + [event], return the next phase.
/// 1-в-1 with React's `nextCallPhase`:
///   idle + localDial      -> outgoing
///   idle + remoteOffer    -> ringing
///   ringing + localAccept -> active
///   outgoing + remoteAccept -> active
///   ANY phase + {localDecline, localEnd, remoteDecline, remoteEnd,
///   noAnswer} -> ended
///   else -> phase (unchanged)
///
/// The "any of these 5 events -> ended" branch fires from ANY phase,
/// matching React (it does NOT gate those on the current phase).
CallPhase nextCallPhase(CallPhase phase, CallEvent event) {
  if (event == CallEvent.localDial && phase == CallPhase.idle) {
    return CallPhase.outgoing;
  }
  if (event == CallEvent.remoteOffer && phase == CallPhase.idle) {
    return CallPhase.ringing;
  }
  if (event == CallEvent.localAccept && phase == CallPhase.ringing) {
    return CallPhase.active;
  }
  if (event == CallEvent.remoteAccept && phase == CallPhase.outgoing) {
    return CallPhase.active;
  }
  if (event == CallEvent.localDecline ||
      event == CallEvent.localEnd ||
      event == CallEvent.remoteDecline ||
      event == CallEvent.remoteEnd ||
      event == CallEvent.noAnswer) {
    return CallPhase.ended;
  }
  return phase;
}

/// Pure no-answer timeout predicate. 1-в-1 with React's
/// `hasNoAnswerTimedOut`: `nowMs - dialAtMs >= NO_ANSWER_TIMEOUT_MS`.
/// Fires at/after the timeout boundary (so `dialAt + timeout - 1` is
/// false, `dialAt + timeout` is true).
bool hasNoAnswerTimedOut(int dialAtMs, int nowMs) {
  return nowMs - dialAtMs >= kNoAnswerTimeoutMs;
}
