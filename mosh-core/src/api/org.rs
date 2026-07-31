//! Org facade.
//!
//! Surfaces the former `org_*` Tauri command group: join, leave, list, poll,
//! DM-offer send/accept/dismiss, group create/accept-offer/dismiss-offer,
//! and group member invite. Poll maps to a `StreamSink`-returning facade
//! function, mirroring the former Tauri event that streamed org snapshots.

// TODO(S1.5): implement the facade functions for this group.
