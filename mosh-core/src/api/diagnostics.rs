//! Diagnostics facade.
//!
//! Surfaces the former Tauri command group that reported app-level health:
//! `app_diagnostics` (aggregate frontend/runtime snapshot) and
//! `native_runtime_status` (per-runtime readiness and missing-dependency
//! messages). Returns plain bridge-friendly structs; no streams.

// TODO(S1.3): implement the facade functions for this group.
