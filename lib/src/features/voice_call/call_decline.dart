/// The app's one no-answer window: an incoming call the local user never
/// picks up is declined with `'no_answer'` once it elapses.
///
/// Equal to mosh-core's `INCOMING_RING_MS`, which ends a native ring with
/// no Flutter attached; change the two together
/// (`mosh-core/src/private_dm_runtime/calls/state.rs`). The caller's
/// `OUTGOING_RING_MS` is longer, so on a healthy link this decline reaches
/// the caller before it gives up on its own.
const Duration kIncomingNoAnswerTimeout = Duration(milliseconds: 30000);

/// The decline reasons the call layer emits, so the orchestration layer can
/// distinguish a user decline from a no-answer timeout.
const String kCallDeclineReasonUser = 'declined';
const String kCallDeclineReasonNoAnswer = 'no_answer';

/// The reason the layer emits when the user cancels an outgoing call or
/// hangs up an active one from the call controls, distinct from a decline.
const String kCallDeclineReasonHangup = 'hangup';
