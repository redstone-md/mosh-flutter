/// The reason the call layer sends when the local user declines an incoming
/// call. mosh-core sends `no_answer` itself once an unanswered call's ring
/// budget is spent.
const String kCallDeclineReasonUser = 'declined';

/// The reason the layer emits when the user cancels an outgoing call or
/// hangs up an active one from the call controls, distinct from a decline.
const String kCallDeclineReasonHangup = 'hangup';
