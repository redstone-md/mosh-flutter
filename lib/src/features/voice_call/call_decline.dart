/// The app's one no-answer window: an incoming call the local user never
/// picks up is declined with `'no_answer'` once it elapses.
///
/// The callee half of a pair agreed with mosh-core. The caller's budget is
/// `CALL_RING_TIMEOUT_MS` (`mosh-core/src/private_dm_runtime.rs`): it
/// re-offers every `CALL_RESEND_MS` and ends the call with the same
/// `"no_answer"` reason once the budget is spent. This side is deliberately
/// the shorter of the two, so on a healthy link the callee's real decline
/// reaches the caller before the caller gives up on its own -- the budget
/// is the backstop for a lost decline, not a competing deadline. Change the
/// two together.
const Duration kIncomingNoAnswerTimeout = Duration(milliseconds: 30000);

/// The decline reasons the call layer emits, so the orchestration layer can
/// distinguish a user decline from a no-answer timeout.
const String kCallDeclineReasonUser = 'declined';
const String kCallDeclineReasonNoAnswer = 'no_answer';

/// The reason the layer emits when the user cancels an outgoing call or
/// hangs up an active one from the call controls, distinct from a decline.
const String kCallDeclineReasonHangup = 'hangup';
