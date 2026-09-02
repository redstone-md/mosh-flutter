//! `flutter_rust_bridge` facade over the mosh-core runtimes.
//!
//! This is the *only* Rust surface the Dart bridge sees, per ADR 0010.
//! The surface has two shapes. The kind-specific facades (`private_dm`,
//! `channel`, `private_group`, `org`, ...) keep the former Tauri commands
//! that are genuinely one kind's: invites, join/create, typed polls and
//! lists, DM offers, the voice-call pipeline. The actions every conversation
//! kind shares — send, retry, attachment send/download/cancel, leave — exist
//! once in `conversation`, kind-tagged and returning a typed error (ADR 0024).
//!
//! The facade stays intentionally thin: it delegates to the existing
//! runtimes (`mosh_runtime`, `private_dm_runtime`, `channel_runtime`,
//! `private_group_runtime`, `org_runtime`, `voice_call_runtime`, etc.)
//! and does not introduce new domain logic. Argument and return types are
//! kept bridge-friendly so `flutter_rust_bridge` can generate the Dart
//! bindings without manual glue.

/// Facade for the `app_diagnostics` / `native_runtime_status` Tauri commands.
pub mod diagnostics;

/// Shared process-global runtime resources (Moss node + attachment store +
/// persistence) + the two mobile-inject knobs (`set_history_dek`,
/// `set_app_data_dir`). Borrowed by every runtime facade.
pub mod shared_runtime;

/// Facade for the `private_dm_*` family of Tauri commands.
pub mod private_dm;

/// Facade for the `channel_*` family of Tauri commands.
pub mod channel;

/// Facade for the `private_group_*` family of Tauri commands.
pub mod private_group;

/// Unified attachment range facade used by the local media HTTP server.
pub mod attachment_stream;

/// Facade for the `org_*` family of Tauri commands.
pub mod org;

/// Facade for the `list_network_interfaces` Tauri command.
pub mod network;

/// Facade for the `detect_vpn` / `get_bind_interface` / VPN-bypass-consent
/// Tauri commands.
pub mod vpn;

/// Facade for the voice-call Opus encoder (real mic capture pipeline:
/// `record` PCM16 -> Rust Opus encode -> Opus packet). See
/// `voice_call_opus_encode`.
pub mod voice_call_opus_encode;

/// Facade for the voice-call Opus decoder + cpal output (real playback
/// pipeline: Opus packet -> Rust decode -> ring buffer -> cpal stream with
/// drift-resync). See `voice_call_playback`.
pub mod voice_call_playback;

/// Facade for the CPAL-backed two-tone voice-call ringtone.
pub mod voice_call_ringtone;

/// The one error the bridge speaks for every conversation kind. See ADR 0024:
/// the shared conversation actions return this instead of a flattened string,
/// so Dart can branch on what to do about a failure rather than on its text.
pub mod conversation_bridge;

/// The six shared conversation actions (ADR 0024), kind-tagged by
/// `BridgeConversationRef` and typed-errored by `ConversationBridgeError`.
pub mod conversation;

/// The kind facades' actions proved to answer the typed bridge error, one
/// live test per runtime. Kept out of the facades so they stay under the
/// file budget.
#[cfg(test)]
mod facade_error_tests;
