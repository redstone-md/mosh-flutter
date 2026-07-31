//! `flutter_rust_bridge` facade over the mosh-core runtimes.
//!
//! This is the *only* Rust surface the Dart bridge sees, per ADR 0010.
//! Each public function in this module corresponds one-to-one to a former
//! Tauri command exposed by the previous `src-tauri` shell. Each function
//! that returns a `StreamSink<T>` corresponds one-to-one to a former Tauri
//! event that streamed frames to the frontend.
//!
//! The facade stays intentionally thin: it delegates to the existing
//! runtimes (`mosh_runtime`, `private_dm_runtime`, `channel_runtime`,
//! `private_group_runtime`, `org_runtime`, `voice_call_runtime`, etc.)
//! and does not introduce new domain logic. Argument and return types are
//! kept bridge-friendly so `flutter_rust_bridge` can generate the Dart
//! bindings without manual glue.
//!
//! Sub-modules group the facade by the former Tauri command surface:
//! diagnostics, private_dm, channel, private_group, org, network, vpn.

/// Facade for the `app_diagnostics` / `native_runtime_status` Tauri commands.
pub mod diagnostics;

/// Facade for the `private_dm_*` family of Tauri commands.
pub mod private_dm;

/// Facade for the `channel_*` family of Tauri commands.
pub mod channel;

/// Facade for the `private_group_*` family of Tauri commands.
pub mod private_group;

/// Facade for the `org_*` family of Tauri commands.
pub mod org;

/// Facade for the `list_network_interfaces` Tauri command.
pub mod network;

/// Facade for the `detect_vpn` / `get_bind_interface` / VPN-bypass-consent
/// Tauri commands.
pub mod vpn;
