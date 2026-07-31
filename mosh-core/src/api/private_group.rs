//! Private-group facade.
//!
//! Surfaces the former `private_group_*` Tauri command group: create, join,
//! send, retry_message, poll, list, close, attachment send/download/cancel,
//! and the send/dismiss DM-offer commands. Poll maps to a
//! `StreamSink`-returning facade function, mirroring the former Tauri event
//! that streamed private-group updates.

// TODO(S1.5): implement the facade functions for this group.
