//! Channel facade.
//!
//! Surfaces the former `channel_*` Tauri command group: join, leave, send,
//! retry_message, poll, list, attachment send/download/cancel, and the
//! send/dismiss DM-offer commands. Poll maps to a `StreamSink`-returning
//! facade function, mirroring the former Tauri event that streamed channel
//! updates.

// TODO(S1.5): implement the facade functions for this group.
