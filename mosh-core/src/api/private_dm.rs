//! Private-DM facade.
//!
//! Surfaces the former `private_dm_*` Tauri command group: invite
//! create/accept, message send/retry, session poll/list/close,
//! attachment send/download/cancel, and voice-call start/accept/decline/
//! end/send-frame/drain-frames. Call-start and frame-drain map to
//! `StreamSink`-returning facade functions, mirroring the former Tauri
//! events that streamed call signaling and media frames.

// TODO(S1.4): implement the facade functions for this group.
